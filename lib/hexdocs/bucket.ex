defmodule Hexdocs.Bucket do
  require Logger

  @special_package_names Map.keys(Application.compile_env!(:hexdocs, :special_packages))
  @gcs_put_debounce Application.compile_env!(:hexdocs, :gcs_put_debounce)

  def upload_index_sitemap(sitemap) do
    upload_content("sitemap", "sitemap.xml", sitemap)
  end

  def upload_package_sitemap(package, sitemap) do
    upload_content("sitemap/#{package}", "#{package}/sitemap.xml", sitemap)
  end

  def upload_package_names_csv(contents) do
    upload_content("package_names.csv", "package_names.csv", contents)
  end

  defp upload_content(key, path, content) do
    opts = [
      content_type: "text/xml",
      cache_control: "public, max-age=3600",
      meta: [{"surrogate-key", key}]
    ]

    Logger.info("Uploading docs_public_bucket #{path}")

    case Hexdocs.Store.put(:docs_public_bucket, path, content, opts) do
      {:ok, 200, _headers, _body} ->
        :ok

      # We get rate limit errors when processing many objects,
      # ignore this for now under the assumption we only get the
      # error when reprocessing
      {:ok, 429, _headers, _body} ->
        :ok
    end

    purge([key])
  end

  def upload(repository, package, version, all_versions, files) do
    latest_version? = Hexdocs.Utils.latest_version?(package, version, all_versions)
    upload_type = upload_type(latest_version?)
    upload_files = list_upload_files(repository, package, version, files, upload_type)
    paths = MapSet.new(upload_files, &elem(&1, 0))

    upload_new_files(upload_files)
    delete_old_docs(repository, package, [version], paths, upload_type)

    Hexdocs.Debouncer.debounce(
      Hexdocs.Debouncer,
      {:docs_config, repository, package},
      @gcs_put_debounce,
      fn ->
        docs_config = build_docs_config(repository, package, version, all_versions, files)
        upload_new_files([docs_config])
      end
    )

    purge_hexdocs_cache(repository, package, [version], upload_type)
    purge([docs_config_cdn_key(repository, package)])
  end

  # For Elixir and Hex we use the docs_config.js included in the tarball
  defp build_docs_config(repository, package, _version, _all_versions, files)
       when package in @special_package_names do
    path = "docs_config.js"
    unversioned_path = repository_path(repository, Path.join([package, path]))
    cdn_key = docs_config_cdn_key(repository, package)
    {"docs_config.js", data} = List.keyfind(files, "docs_config.js", 0)
    {unversioned_path, cdn_key, data, public?(repository)}
  end

  # TODO: don't include retired versions?
  defp build_docs_config(repository, package, version, all_versions, _files) do
    versions =
      if version in all_versions do
        all_versions
      else
        Enum.sort([version | all_versions], &(Version.compare(&1, &2) == :gt))
      end

    latest_version = Hexdocs.Utils.latest_version(versions)

    versions =
      for version <- versions do
        map = %{
          version: "v#{version}",
          url: Hexdocs.Utils.hexdocs_url(repository, "/#{package}/#{version}")
        }

        if latest_version == version do
          Map.put(map, :latest, true)
        else
          map
        end
      end

    search =
      if repository == "hexpm" do
        [%{name: package, version: Version.to_string(version)}]
      end

    path = "docs_config.js"
    unversioned_path = repository_path(repository, Path.join([package, path]))
    cdn_key = docs_config_cdn_key(repository, package)

    data = [
      "var versionNodes = ",
      Jason.encode_to_iodata!(versions),
      ";\n",
      if search do
        [
          "var searchNodes = ",
          Jason.encode_to_iodata!(search),
          ";"
        ]
      else
        []
      end
    ]

    {unversioned_path, cdn_key, data, public?(repository)}
  end

  defp docs_config_cdn_key(repository, package) do
    "docspage/#{repository_cdn_key(repository)}#{package}/docs_config.js"
  end

  def delete(repository, package, version, all_versions) do
    deleting_latest_version? = Hexdocs.Utils.latest_version?(package, version, all_versions)
    new_latest_version = Hexdocs.Utils.latest_version(all_versions -- [version])

    cond do
      deleting_latest_version? && new_latest_version ->
        key = build_key(repository, package, new_latest_version)
        body = Hexdocs.Store.get(:repo_bucket, key)

        case Hexdocs.Tar.unpack(body, repository: repository, package: package, version: version) do
          {:ok, files} ->
            upload_files =
              list_upload_files(repository, package, new_latest_version, files, :both)

            paths = MapSet.new(upload_files, &elem(&1, 0))
            update_versions = [version, new_latest_version]

            upload_new_files(upload_files)
            delete_old_docs(repository, package, update_versions, paths, :both)
            purge_hexdocs_cache(repository, package, update_versions, :both)

          {:error, reason} ->
            Logger.error("Failed unpack #{repository}/#{package} #{version}: #{reason}")
        end

      deleting_latest_version? ->
        delete_old_docs(repository, package, [version], [], :both)
        purge_hexdocs_cache(repository, package, [version], :both)

      true ->
        delete_old_docs(repository, package, [version], [], :versioned)
        purge_hexdocs_cache(repository, package, [version], :versioned)
    end
  end

  defp build_key("hexpm", package, version) do
    Path.join("docs", "#{package}-#{version}.tar.gz")
  end

  defp build_key(repository, package, version) do
    Path.join(["repos", repository, "docs", "#{package}-#{version}.tar.gz"])
  end

  defp list_upload_files(repository, package, version, files, upload_type) do
    Enum.flat_map(files, fn
      {"docs_config.js", _data} ->
        []

      {path, data} ->
        versioned_path =
          repository_path(repository, Path.join([package, to_string(version), path]))

        cdn_key = docspage_versioned_cdn_key(repository, package, version)
        versioned = {versioned_path, cdn_key, data, public?(repository)}

        unversioned_path = repository_path(repository, Path.join([package, path]))
        cdn_key = docspage_unversioned_cdn_key(repository, package)
        unversioned = {unversioned_path, cdn_key, data, public?(repository)}

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
      timeout: 60_000
    )
    |> Hexdocs.Utils.raise_async_stream_error()
    |> Stream.run()
  end

  defp delete_old_docs(repository, package, versions, paths, upload_type) do
    bucket = bucket(public?(repository))
    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_keys =
      case {upload_type, versions} do
        {:both, _} ->
          Hexdocs.Store.list(bucket, repository_path(repository, "#{package}/"))

        {:versioned, [version]} ->
          Hexdocs.Store.list(bucket, repository_path(repository, "#{package}/#{version}/"))
      end

    keys_to_delete =
      Enum.filter(
        existing_keys,
        &delete_key?(&1, paths, repository, package, versions, upload_type)
      )

    Enum.each(keys_to_delete, fn key ->
      Logger.info("Deleting #{bucket} #{key}")
    end)

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
        {:ok, _} ->
          # Current (/ecto/0.8.1/...)
          Enum.any?(versions, fn version ->
            is_struct(version, Version) and Version.compare(first, version) == :eq
          end)

        :error ->
          if package in @special_package_names do
            # skip main and MAJOR.MINOR
            first != "main" and Version.parse(first <> ".0") == :error
          else
            # Top-level docs, don't match version directories (/ecto/:version/*)
            upload_type in [:both, :unversioned]
          end
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
  # Don't use Path.join as it removes trailing / which is needed for bucket listing
  defp repository_path(repository, path), do: Enum.join([repository, "/", path])

  defp purge_hexdocs_cache("hexpm", package, versions, :both) do
    keys = Enum.map(versions, &docspage_versioned_cdn_key("hexpm", package, &1))
    purge([docspage_unversioned_cdn_key("hexpm", package)] ++ keys)
  end

  defp purge_hexdocs_cache("hexpm", package, versions, :versioned) do
    versions
    |> Enum.map(&docspage_versioned_cdn_key("hexpm", package, &1))
    |> purge()
  end

  defp purge_hexdocs_cache("hexpm", package, _versions, :unversioned) do
    purge([docspage_unversioned_cdn_key("hexpm", package)])
  end

  defp purge_hexdocs_cache(_repository, _package, _version, _publish_unversioned?) do
    :ok
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

  defp public?("hexpm"), do: true
  defp public?(_), do: false

  defp purge(keys) do
    Logger.info("Purging fastly_hexdocs #{Enum.join(keys, " ")}")
    Hexdocs.CDN.purge_key(:fastly_hexdocs, keys)
  end

  defp put(bucket, key, data, opts) do
    Logger.info("Uploading #{bucket} #{key}")
    Hexdocs.Store.put!(bucket, key, data, opts)
  end
end
