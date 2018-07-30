defmodule Hexdocs.Bucket do
  # TODO: When deleting the current stable version (main docs) we should copy docs
  # to build new main docs, or delete main docs if it was the last version

  def upload(repository, package, version, all_versions, files) do
    publishing_unversioned? = publishing_unversioned?(version, all_versions)
    upload_files = list_upload_files(repository, package, version, files, publishing_unversioned?)
    paths = MapSet.new(upload_files, &elem(&1, 0))

    delete_old_docs(repository, package, version, paths, publishing_unversioned?)
    upload_new_files(upload_files)
    # purge_hexdocs_cache(repository, package, version, publishing_unversioned?)
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
      versioned_path = Path.join([repository, package, to_string(version), path])
      cdn_key = docspage_versioned_cdn_key(repository, package, version)
      versioned = {versioned_path, cdn_key, data}

      unversioned_path = Path.join([repository, package, path])
      cdn_key = docspage_unversioned_cdn_key(repository, package)
      unversioned = {unversioned_path, cdn_key, data}

      if publishing_unversioned? do
        [versioned, unversioned]
      else
        [versioned]
      end
    end)
  end

  defp upload_new_files(files) do
    Enum.map(files, fn {store_key, cdn_key, data} ->
      surrogate_key = {"surrogate-key", cdn_key}
      surrogate_control = {"surrogate-control", "max-age=604800"}

      # NOTE: private cache-control
      opts =
        content_type(store_key)
        |> Keyword.put(:cache_control, "private, max-age=3600")
        |> Keyword.put(:meta, [surrogate_key, surrogate_control])

      {store_key, data, opts}
    end)
    |> Task.async_stream(
      fn {key, data, opts} ->
        Hexdocs.Store.put(:docs_bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Stream.run()
  end

  defp delete_old_docs(repository, package, version, paths, publish_unversioned?) do
    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys = Hexdocs.Store.list(:docs_bucket, "#{repository}/#{package}/")

    keys_to_delete =
      Enum.filter(
        existing_keys,
        &delete_key?(&1, paths, repository, package, version, publish_unversioned?)
      )

    Hexdocs.Store.delete_many(:docs_bucket, keys_to_delete)
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

  defp docspage_versioned_cdn_key(repository, package, version) do
    "docspage/#{repository_cdn_key(repository)}#{package}/#{version}"
  end

  defp docspage_unversioned_cdn_key(repository, package) do
    "docspage/#{repository_cdn_key(repository)}#{package}"
  end

  defp repository_cdn_key("hexpm"), do: ""
  defp repository_cdn_key(repository), do: "#{repository}-"
end
