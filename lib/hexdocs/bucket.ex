defmodule Hexdocs.Bucket do
  # TODO: When deleting the current stable version (main docs) we should copy docs
  # to build new main docs, or delete main docs if it was the last version

  def upload(repository, package, version, all_versions, files) do
    publishing_unversioned? = publishing_unversioned?(version, all_versions)
    upload_files = list_upload_files(repository, package, version, files, publishing_unversioned?)
    paths = MapSet.new(upload_files, &elem(&1, 0))

    delete_old_docs(repository, package, version, paths, publishing_unversioned?)
    upload_new_files(upload_files)
    purge_hexdocs_cache(repository, package, version, publishing_unversioned?)
  end

  defp publishing_unversioned?(version, all_versions) do
    pre_release? = version.pre != []
    first_release? = all_versions == []
    all_pre_releases? = Enum.all?(all_versions, &(&1.pre != []))

    cond do
      first_release? ->
        true

      all_pre_releases? ->
        latest_version = List.first(all_versions)
        Version.compare(version, latest_version) in [:eq, :gt]

      pre_release? ->
        false

      true ->
        nonpre_versions = Enum.filter(all_versions, &(&1.pre == []))
        latest_version = List.first(nonpre_versions)
        Version.compare(version, latest_version) in [:eq, :gt]
    end
  end

  defp list_upload_files(repository, package, version, files, publishing_unversioned?) do
    Enum.flat_map(files, fn {path, data} ->
      public? = repository == "hexpm"
      versioned_path = repository_path(repository, Path.join([package, to_string(version), path]))
      cdn_key = docspage_versioned_cdn_key(repository, package, version)
      versioned = {versioned_path, cdn_key, data, public?}

      unversioned_path = repository_path(repository, Path.join([package, path]))
      cdn_key = docspage_unversioned_cdn_key(repository, package)
      unversioned = {unversioned_path, cdn_key, data, public?}

      if publishing_unversioned? do
        [versioned, unversioned]
      else
        [versioned]
      end
    end)
  end

  defp upload_new_files(files) do
    Enum.map(files, fn {store_key, cdn_key, data, public?} ->
      meta = [
        {"surrogate-key", cdn_key},
        {"surrogate-control", "public, max-age=604800"}
      ]

      opts =
        content_type(store_key)
        |> Keyword.put(:cache_control, cache_control(public?))
        |> Keyword.put(:meta, meta)

      {bucket(public?), store_key, data, opts}
    end)
    |> Task.async_stream(
      fn {bucket, key, data, opts} ->
        Hexdocs.Store.put(bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Stream.run()
  end

  defp delete_old_docs(repository, package, version, paths, publish_unversioned?) do
    public? = repository == "hexpm"
    bucket = bucket(public?)
    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys = Hexdocs.Store.list(bucket, "#{repository}/#{package}/")

    keys_to_delete =
      Enum.filter(
        existing_keys,
        &delete_key?(&1, paths, repository, package, version, publish_unversioned?)
      )

    Hexdocs.Store.delete_many(bucket, keys_to_delete)
  end

  defp delete_key?(key, paths, repository, package, version, publish_unversioned?) do
    # Don't delete if we are going to overwrite with new files, this
    # removes the downtime between a deleted and added page
    if key in paths do
      false
    else
      first =
        key
        |> Path.relative_to(Path.join(repository, package))
        |> Path.split()
        |> hd()

      case Version.parse(first) do
        {:ok, first} ->
          # Current (/ecto/0.8.1/...)
          Version.compare(first, version) == :eq

        :error ->
          # Top-level docs, don't match version directories (/ecto/...)
          publish_unversioned?
      end
    end
  end

  defp content_type(path) do
    case Path.extname(path) do
      "." <> ext -> [content_type: MIME.type(ext)]
      "" -> []
    end
  end

  defp bucket(true = _public?), do: :docs_public_bucket
  defp bucket(false = _public?), do: :docs_private_bucket

  defp cache_control(true = _public?), do: "public, max-age=3600"
  defp cache_control(false = _public?), do: "private, max-age=3600"

  defp repository_path("hexpm", path), do: path
  defp repository_path(repository, path), do: Path.join(repository, path)

  defp purge_hexdocs_cache("hexpm", package, version, publish_unversioned?) do
    if publish_unversioned? do
      Task.async_stream([
        fn -> purge_versioned_docspage("hexpm", package, version) end,
        fn -> purge_unversioned_docspage("hexpm", package) end
      ], fn fun -> fun.() end)
      |> Stream.run()
    else
      purge_versioned_docspage("hexpm", package, version)
    end
  end

  defp purge_hexdocs_cache(_repository, _package, _version, _publish_unversioned?) do
    :ok
  end

  defp purge_versioned_docspage(repository, package, version) do
    key = docspage_versioned_cdn_key(repository, package, version)
    Hexdocs.CDN.purge_key(:fastly_hexdocs, key)
  end

  defp purge_unversioned_docspage(repository, package) do
    key = docspage_unversioned_cdn_key(repository, package)
    Hexdocs.CDN.purge_key(:fastly_hexdocs, key)
  end

  defp docspage_versioned_cdn_key(repository, package, version) do
    "docspage/#{repository_cdn_key(repository)}#{package}/#{version}"
  end

  defp docspage_unversioned_cdn_key(repository, package) do
    "docspage/#{repository_cdn_key(repository)}#{package}"
  end

  defp repository_cdn_key("hexpm"), do: ""
  defp repository_cdn_key(repository), do: "#{repository}-"
end
