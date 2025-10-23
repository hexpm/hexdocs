defmodule Hexdocs.Queue do
  use Broadway
  require Logger

  @special_packages Application.compile_env!(:hexdocs, :special_packages)
  @special_package_names Map.keys(@special_packages)
  @gcs_put_debounce Application.compile_env!(:hexdocs, :gcs_put_debounce)

  def start_link(_opts) do
    url = Application.fetch_env!(:hexdocs, :queue_id)
    producer = Application.fetch_env!(:hexdocs, :queue_producer)
    concurrency = Application.fetch_env!(:hexdocs, :queue_concurrency)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          producer,
          queue_url: url,
          max_number_of_messages: concurrency,
          wait_time_seconds: 10,
          visibility_timeout: 300
        },
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: concurrency,
          min_demand: 0,
          max_demand: 1
        ]
      ]
    )
  end

  @impl true
  def handle_message(_processor, %Broadway.Message{} = message, _context) do
    message
    |> Broadway.Message.update_data(&JSON.decode!/1)
    |> handle_message()
  end

  @doc false
  def handle_message(%{data: %{"Event" => "s3:TestEvent"}} = message) do
    Sentry.Context.set_extra_context(%{queue_event: "s3:TestEvent"})

    message
  end

  def handle_message(%{data: %{"Records" => records}} = message) do
    Enum.each(records, &handle_record/1)
    message
  end

  def handle_message(%{data: %{"hexdocs:sitemap" => key}} = message) do
    Sentry.Context.set_extra_context(%{queue_event: "hexdocs:sitemap"})
    Logger.info("#{key}: start")

    case key_components(key) do
      {:ok, repository, package, version} ->
        body = Hexdocs.Store.get(:repo_bucket, key)

        case Hexdocs.Tar.unpack(body, repository: repository, package: package, version: version) do
          {:ok, files} ->
            update_index_sitemap(repository, key)
            update_package_sitemap(repository, key, package, files)
            Logger.info("#{key}: done")

          {:error, reason} ->
            Logger.error("Failed unpack #{repository}/#{package} #{version}: #{reason}")
        end

      :error ->
        Logger.info("#{key}: skip")
    end

    message
  end

  def handle_message(%{data: %{"hexdocs:upload" => key}} = message) do
    process_docs(key, :upload)
    message
  end

  def handle_message(%{data: %{"hexdocs:search" => key}} = message) do
    process_docs(key, :search)
    message
  end

  defp process_docs(key, type) do
    start = System.os_time(:millisecond)
    event_name = if type == :upload, do: "hexdocs:upload", else: "hexdocs:search"
    log_prefix = if type == :upload, do: "UPLOAD", else: "SEARCH INDEX"

    Sentry.Context.set_extra_context(%{queue_event: event_name})
    Logger.info("#{log_prefix} #{key}")

    case key_components(key) do
      {:ok, repository, package, version} ->
        Sentry.Context.set_extra_context(%{
          queue_event: event_name,
          repository: repository,
          package: package,
          version: version
        })

        body = Hexdocs.Store.get(:repo_bucket, key)

        case type do
          :upload ->
            process_upload(key, repository, package, version, body, start)

          :search ->
            process_search(key, package, version, body, start)
        end

      :error ->
        Logger.info("#{key}: skip")
    end
  end

  defp process_upload(key, repository, package, version, body, start) do
    {version, all_versions} =
      if package in @special_package_names do
        version =
          case Version.parse(version) do
            {:ok, version} ->
              version

            # main or MAJOR.MINOR
            :error ->
              version
          end

        all_versions = Hexdocs.SourceRepo.versions!(Map.fetch!(@special_packages, package))
        {version, all_versions}
      else
        version = Version.parse!(version)
        all_versions = all_versions(repository, package)
        {version, all_versions}
      end

    case Hexdocs.Tar.unpack(body, repository: repository, package: package, version: version) do
      {:ok, files} ->
        files = rewrite_files(files)

        Hexdocs.Bucket.upload(
          repository,
          package,
          version,
          all_versions,
          files
        )

        if Hexdocs.Utils.latest_version?(package, version, all_versions) do
          update_index_sitemap(repository, key)
          update_package_sitemap(repository, key, package, files)
          update_package_names_csv(repository)
        end

        elapsed = System.os_time(:millisecond) - start
        Logger.info("FINISHED UPLOADING DOCS #{key} #{elapsed}ms")

      {:error, reason} ->
        Logger.error("Failed unpack #{repository}/#{package} #{version}: #{reason}")
    end
  end

  defp process_search(key, package, version, body, start) do
    case Version.parse(version) do
      {:ok, version} ->
        case Hexdocs.Tar.unpack(body, package: package, version: version) do
          {:ok, files} ->
            update_search_index(key, package, version, files)

            elapsed = System.os_time(:millisecond) - start
            Logger.info("FINISHED INDEXING DOCS #{key} #{elapsed}ms")

          {:error, reason} ->
            Logger.error("Failed unpack #{package} #{version}: #{reason}")
        end

      :error when package in @special_package_names ->
        # Skip for special packages, it's probably a tag push that's not valid semver
        # and we don't need to index those
        :ok
    end
  end

  @impl true
  def handle_batch(_batcher, messages, _batch_info, _context) do
    messages
  end

  defp handle_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}) do
    key = s3["object"]["key"]
    Logger.info("OBJECT CREATED #{key}")

    case key_components(key) do
      {:ok, repository, _package, _version} ->
        Sentry.Context.set_extra_context(%{
          queue_event: "ObjectCreated",
          repository: repository
        })

        # Publish upload message
        publish_message(%{"hexdocs:upload" => key})

        # Publish search message for hexpm repository
        if repository == "hexpm" do
          publish_message(%{"hexdocs:search" => key})
        end

        Logger.info("PUBLISHED MESSAGES FOR #{key}")

      :error ->
        :skip
    end
  end

  defp handle_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}) do
    key = s3["object"]["key"]
    start = System.os_time(:millisecond)
    Logger.info("OBJECT DELETED #{key}")

    case key_components(key) do
      {:ok, repository, package, version} when package not in @special_package_names ->
        Sentry.Context.set_extra_context(%{
          queue_event: "ObjectRemoved",
          repository: repository,
          package: package,
          version: version
        })

        version = Version.parse!(version)
        all_versions = all_versions(repository, package)
        Hexdocs.Bucket.delete(repository, package, version, all_versions)
        update_index_sitemap(repository, key)

        if repository == "hexpm" do
          Hexdocs.Search.delete(package, version)
        end

        elapsed = System.os_time(:millisecond) - start
        Logger.info("FINISHED DELETING DOCS #{key} #{elapsed}ms")
        :ok

      {:ok, _repository, _package, _version} ->
        :skip

      :error ->
        :skip
    end
  end

  defp key_components(key) do
    case Path.split(key) do
      ["repos", repository, "docs", file] ->
        {package, version} = filename_to_release(file)
        {:ok, repository, package, version}

      ["docs", file] ->
        {package, version} = filename_to_release(file)
        {:ok, "hexpm", package, version}

      _ ->
        :error
    end
  end

  defp filename_to_release(file) do
    base = Path.basename(file, ".tar.gz")
    [package, version] = String.split(base, "-", parts: 2)
    {package, version}
  end

  defp rewrite_files(files) do
    Enum.map(files, fn {path, content} ->
      {path, Hexdocs.FileRewriter.run(path, content)}
    end)
  end

  defp all_versions(repository, package) do
    if package = Hexdocs.Hexpm.get_package(repository, package) do
      package["releases"]
      |> Enum.filter(& &1["has_docs"])
      |> Enum.map(&Version.parse!(&1["version"]))
      |> Enum.sort(&(Version.compare(&1, &2) == :gt))
    else
      []
    end
  end

  defp update_index_sitemap("hexpm", key) do
    Logger.info("UPDATING INDEX SITEMAP #{key}")

    Hexdocs.Debouncer.debounce(Hexdocs.Debouncer, :sitemap_index, @gcs_put_debounce, fn ->
      body = Hexdocs.Hexpm.hexdocs_sitemap()
      Hexdocs.Bucket.upload_index_sitemap(body)
    end)

    Logger.info("UPDATED INDEX SITEMAP #{key}")
  end

  defp update_index_sitemap(_repository, _key) do
    :ok
  end

  defp update_package_sitemap("hexpm", key, package, files) do
    Logger.info("UPDATING PACKAGE SITEMAP #{key}")

    pages = for {path, _content} <- files, Path.extname(path) == ".html", do: path
    body = Hexdocs.PackageSitemap.render(package, pages, DateTime.utc_now())
    Hexdocs.Bucket.upload_package_sitemap(package, body)

    Logger.info("UPDATED PACKAGE SITEMAP #{key}")
  end

  defp update_package_sitemap(_repository, _key, _package, _files) do
    :ok
  end

  defp update_package_names_csv("hexpm") do
    Logger.info("UPDATING package_names.csv")

    case Hexdocs.HexRepo.get_names() do
      {:ok, names} ->
        csv = for name <- names, do: [name, "\n"]
        Hexdocs.Bucket.upload_package_names_csv(csv)

      {:error, reason} ->
        Logger.error(inspect(reason))
    end

    Logger.info("UPDATED package_names.csv")
  end

  defp update_package_names_csv(_repository) do
    :ok
  end

  defp update_search_index(key, package, version, files) do
    with {proglang, items} <- Hexdocs.Search.find_search_items(package, version, files) do
      Logger.info("UPDATING SEARCH INDEX #{key}")
      Hexdocs.Search.index(package, version, proglang, items)
      Logger.info("UPDATED SEARCH INDEX #{key}")
    end
  end

  defp publish_message(map) do
    queue = Application.fetch_env!(:hexdocs, :queue_id)
    message = JSON.encode!(map)

    ExAws.SQS.send_message(queue, message)
    |> ExAws.request!()
  end

  @doc false
  def paths_for_sitemaps() do
    key_regex = ~r"docs/(.*)-(.*).tar.gz$"

    Hexdocs.Store.list(:repo_bucket, "docs/")
    |> Stream.filter(&Regex.match?(key_regex, &1))
    |> Stream.map(fn path ->
      {package, version} = filename_to_release(path)
      {path, package, version}
    end)
    |> Stream.chunk_by(fn {_, package, _} -> package end)
    |> Stream.flat_map(fn entries ->
      entries = Enum.sort_by(entries, fn {_, _, version} -> version end, {:desc, Version})
      all_versions = for {_, _, version} <- entries, do: Version.parse!(version)

      List.wrap(
        Enum.find_value(entries, fn {path, package, version} ->
          Hexdocs.Utils.latest_version?(package, Version.parse!(version), all_versions) && path
        end)
      )
    end)
  end
end
