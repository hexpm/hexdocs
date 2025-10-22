defmodule Hexdocs do
  @key_regex ~r"docs/(.*)-(.*).tar.gz$"

  def process_object(type, key) when type in [:upload, :search] do
    publish_message(type, key)
  end

  def process_all_objects(type) when type in [:upload, :search] do
    (Hexdocs.Store.list(:repo_bucket, "docs/") ++ Hexdocs.Store.list(:repo_bucket, "repos/"))
    |> Enum.shuffle()
    |> batched_send(type)
  end

  def batched_send(keys, type) when type in [:upload, :search] do
    keys
    |> Stream.filter(&Regex.match?(@key_regex, &1))
    |> Stream.map(&build_message(type, &1))
    |> Task.async_stream(&send_message/1, max_concurrency: 10, ordered: false, timeout: 60_000)
    |> Stream.run()
  end

  defp build_message(:upload, key) do
    %{"hexdocs:upload" => key}
  end

  defp build_message(:search, key) do
    %{"hexdocs:search" => key}
  end

  defp send_message(map) do
    queue = Application.fetch_env!(:hexdocs, :queue_id)
    message = Jason.encode!(map)

    ExAws.SQS.send_message(queue, message)
    |> ExAws.request!()
  end

  def process_all_sitemaps(paths) do
    paths
    |> Stream.map(&%{"hexdocs:sitemap" => &1})
    |> Task.async_stream(&send_message/1, max_concurrency: 10, ordered: false, timeout: 60_000)
    |> Stream.run()
  end

  def publish_upload_message(key) do
    publish_message(:upload, key)
  end

  def publish_search_message(key) do
    publish_message(:search, key)
  end

  def publish_message(:upload, key) do
    %{"hexdocs:upload" => key}
    |> send_message()
  end

  def publish_message(:search, key) do
    %{"hexdocs:search" => key}
    |> send_message()
  end
end
