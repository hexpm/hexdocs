defmodule Hexdocs.Queue do
  use Broadway
  require Logger

  @ignore_packages ~w(eex elixir ex_unit iex logger mix hex)

  def start_link(_opts) do
    url = Application.fetch_env!(:hexdocs, :queue_id)
    producer = Application.fetch_env!(:hexdocs, :queue_producer)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          producer,
          queue_url: url,
          max_number_of_messages: 8,
          wait_time_seconds: 10,
          visibility_timeout: 120
        },
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: 2,
          min_demand: 1,
          max_demand: 2
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

  @impl true
  def handle_batch(_batcher, messages, _batch_info, _context) do
    messages
  end

  defp handle_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}) do
    key = s3["object"]["key"]
    Logger.info("OBJECT CREATED #{key}")

    case key_components(key) do
      {:ok, repository, package, version} ->
        body = Hexdocs.Store.get(:repo_bucket, key)

        # TODO: Handle errors
        {:ok, files} = Hexdocs.Tar.unpack(body)
        files = rewrite_files(files)
        version = Version.parse!(version)
        all_versions = all_versions(repository, package)
        Hexdocs.Bucket.upload(repository, package, version, all_versions, files)
        update_sitemap(repository, key)
        Logger.info("FINISHED UPLOADING DOCS #{key}")

      :error ->
        :skip
    end
  end

  defp handle_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}) do
    key = s3["object"]["key"]
    Logger.info("OBJECT DELETED #{key}")

    case key_components(key) do
      {:ok, repository, package, version} ->
        version = Version.parse!(version)
        all_versions = all_versions(repository, package)
        Hexdocs.Bucket.delete(repository, package, version, all_versions)
        update_sitemap(repository, key)
        Logger.info("FINISHED DELETING DOCS #{key}")
        :ok

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
        case filename_to_release(file) do
          {package, _version} when package in @ignore_packages -> :error
          {package, version} -> {:ok, "hexpm", package, version}
        end

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

  defp update_sitemap("hexpm", key) do
    Logger.info("UPDATING SITEMAP #{key}")

    body = Hexdocs.Hexpm.hexdocs_sitemap()
    Hexdocs.Bucket.upload_sitemap(body)

    Logger.info("UPDATED SITEMAP #{key}")
  end

  defp update_sitemap(_repository, _key) do
    :ok
  end
end
