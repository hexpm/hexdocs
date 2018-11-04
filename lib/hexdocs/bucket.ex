defmodule Hexdocs.Bucket do
  require Logger

  def upload_sitemap(sitemap) do
    opts = [
      content_type: "text/xml",
      cache_control: "public, max-age=3600",
      meta: [{"surrogate-key", "sitemap"}]
    ]

    Hexdocs.Store.put(:docs_public_bucket, "sitemap.xml", sitemap, opts)
    purge(:fastly_hexdocs, "sitemap")
  end

  def upload(repository, package, version, all_versions, files) do
    latest_version? = latest_version?(version, all_versions)
    upload_type = upload_type(latest_version?)
    upload_files = list_upload_files(repository, package, version, files, upload_type)
    paths = MapSet.new(upload_files, &elem(&1, 0))

    upload_new_files(upload_files)
    delete_old_docs(repository, package, [version], paths, upload_type)
    purge_hexdocs_cache(repository, package, [version], upload_type)
  end

  def delete(repository, package, version, all_versions) do
    deleting_latest_version? = latest_version?(version, all_versions)
    new_latest_version = latest_version(all_versions -- [version])

    cond do
      deleting_latest_version? && new_latest_version ->
        key = build_key(repository, package, new_latest_version)
        body = Hexdocs.Store.get(:repo_bucket, key)
        {:ok, files} = Hexdocs.Tar.unpack(body)

        upload_files = list_upload_files(repository, package, new_latest_version, files, :both)
        paths = MapSet.new(upload_files, &elem(&1, 0))
        update_versions = [version, new_latest_version]

        upload_new_files(upload_files)
        delete_old_docs(repository, package, update_versions, paths, :both)
        purge_hexdocs_cache(repository, package, update_versions, :both)

      deleting_latest_version? ->
        delete_old_docs(repository, package, [version], [], :both)
        purge_hexdocs_cache(repository, package, [version], :both)

      true ->
        delete_old_docs(repository, package, [version], [], :versioned)
        purge_hexdocs_cache(repository, package, [version], :versioned)
    end
  end

  defp latest_version?(_version, []) do
    true
  end

  defp latest_version?(version, all_versions) do
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

  defp latest_version(versions) do
    Enum.find(versions, &(&1.pre != [])) || List.first(versions)
  end

  defp build_key("hexpm", package, version) do
    Path.join("docs", "#{package}-#{version}.tar.gz")
  end

  defp build_key(repository, package, version) do
    Path.join(["repos", repository, "docs", "#{package}-#{version}.tar.gz"])
  end

  defp list_upload_files(repository, package, version, files, upload_type) do
    Enum.flat_map(files, fn {path, data} ->
      public? = repository == "hexpm"
      versioned_path = repository_path(repository, Path.join([package, to_string(version), path]))
      cdn_key = docspage_versioned_cdn_key(repository, package, version)
      versioned = {versioned_path, cdn_key, data, public?}

      unversioned_path = repository_path(repository, Path.join([package, path]))
      cdn_key = docspage_unversioned_cdn_key(repository, package)
      unversioned = {unversioned_path, cdn_key, data, public?}

      case upload_type do
        :both -> [versioned, unversioned]
        :versioned -> [versioned]
        :unversioned -> [unversioned]
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
        put(bucket, key, data, opts)
      end,
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Stream.run()
  end

  defp delete_old_docs(repository, package, versions, paths, upload_type) do
    public? = repository == "hexpm"
    bucket = bucket(public?)
    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys = Hexdocs.Store.list(bucket, repository_path(repository, "#{package}/"))

    keys_to_delete =
      Enum.filter(
        existing_keys,
        &delete_key?(&1, paths, repository, package, versions, upload_type)
      )

    Hexdocs.Store.delete_many(bucket, keys_to_delete)
  end

  defp delete_key?(key, paths, repository, package, versions, upload_type) do
    # Don't delete if we are going to overwrite with new files, this
    # removes the downtime between a deleted and added page
    if key in paths do
      false
    else
      first =
        key
        |> Path.relative_to(repository_path(repository, package))
        |> Path.split()
        |> hd()

      case Version.parse(first) do
        {:ok, first} ->
          # Current (/ecto/0.8.1/...)
          Enum.any?(versions, fn version ->
            Version.compare(first, version) == :eq
          end)

        :error ->
          # Top-level docs, don't match version directories (/ecto/...)
          upload_type in [:both, :unversioned]
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

  defp purge_hexdocs_cache("hexpm", package, versions, :both) do
    versions
    |> Enum.map(fn version ->
      fn -> purge_versioned_docspage("hexpm", package, version) end
    end)
    |> Kernel.++([fn -> purge_unversioned_docspage("hexpm", package) end])
    |> run_async_stream()
  end

  defp purge_hexdocs_cache("hexpm", package, versions, :versioned) do
    versions
    |> Enum.map(fn version ->
      fn -> purge_versioned_docspage("hexpm", package, version) end
    end)
    |> run_async_stream()
  end

  defp purge_hexdocs_cache("hexpm", package, _versions, :unversioned) do
    purge_unversioned_docspage("hexpm", package)
  end

  defp purge_hexdocs_cache(_repository, _package, _version, _publish_unversioned?) do
    :ok
  end

  defp purge_versioned_docspage(repository, package, version) do
    key = docspage_versioned_cdn_key(repository, package, version)
    purge(:fastly_hexdocs, key)
  end

  defp purge_unversioned_docspage(repository, package) do
    key = docspage_unversioned_cdn_key(repository, package)
    purge(:fastly_hexdocs, key)
  end

  defp docspage_versioned_cdn_key(repository, package, version) do
    "docspage/#{repository_cdn_key(repository)}#{package}/#{version}"
  end

  defp docspage_unversioned_cdn_key(repository, package) do
    "docspage/#{repository_cdn_key(repository)}#{package}"
  end

  defp repository_cdn_key("hexpm"), do: ""
  defp repository_cdn_key(repository), do: "#{repository}-"

  defp upload_type(true = _latest_version?), do: :both
  defp upload_type(false = _latest_version?), do: :versioned

  defp run_async_stream([]) do
    :ok
  end

  defp run_async_stream([fun]) do
    fun.()
  end

  defp run_async_stream(funs) do
    funs
    |> Task.async_stream(fn fun -> fun.() end)
    |> Stream.run()
  end

  defp purge(service, key) do
    Logger.info("Purging #{service} #{key}")
    Hexdocs.CDN.purge_key(:fastly_hexdocs, key)
  end

  defp put(bucket, key, data, opts) do
    Logger.info("Uploading #{bucket} #{key}")
    Hexdocs.Store.put(bucket, key, data, opts)
  end
end
