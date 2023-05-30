defmodule Hexdocs.Queue do
  use Broadway
  require Logger

  @special_packages Application.compile_env!(:hexdocs, :special_packages)
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
    |> Broadway.Message.update_data(&Jason.decode!/1)
    |> handle_message()
  end

  @doc false
  def handle_message(%{data: %{"Event" => "s3:TestEvent"}} = message) do
    message
  end

  def handle_message(%{data: %{"Records" => records}} = message) do
    Enum.each(records, &handle_record/1)
    message
  end

  def handle_message(%{data: %{"hexdocs:sitemap" => key}} = message) do
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

  @impl true
  def handle_batch(_batcher, messages, _batch_info, _context) do
    messages
  end

  defp handle_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}) do
    start = System.os_time(:millisecond)
    key = s3["object"]["key"]
    Logger.info("OBJECT CREATED #{key}")

    case key_components(key) do
      {:ok, repository, package, version} ->
        body = Hexdocs.Store.get(:repo_bucket, key)

        {version, all_versions} =
          if package in @special_packages do
            {version, []}
          else
            {Version.parse!(version), all_versions(repository, package)}
          end

        case Hexdocs.Tar.unpack(body, repository: repository, package: package, version: version) do
          {:ok, files} ->
            files = rewrite_files(files)
            Hexdocs.Bucket.upload(repository, package, version, all_versions, files)

            if Hexdocs.Utils.latest_version?(package, version, all_versions) do
              update_index_sitemap(repository, key)
              update_package_sitemap(repository, key, package, files)
            end

            elapsed = System.os_time(:millisecond) - start
            Logger.info("FINISHED UPLOADING DOCS #{key} #{elapsed}ms")

          {:error, reason} ->
            Logger.error("Failed unpack #{repository}/#{package} #{version}: #{reason}")
        end

      :error ->
        :skip
    end
  end

  defp handle_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}) do
    key = s3["object"]["key"]
    Logger.info("OBJECT DELETED #{key}")

    case key_components(key) do
      {:ok, repository, package, version} when package not in @special_packages ->
        version = Version.parse!(version)
        all_versions = all_versions(repository, package)
        Hexdocs.Bucket.delete(repository, package, version, all_versions)
        update_index_sitemap(repository, key)
        Logger.info("FINISHED DELETING DOCS #{key}")
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
