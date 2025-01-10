defmodule Hexdocs do
  @key_regex ~r"docs/(.*)-(.*).tar.gz$"

  def process_object(key) do
    key
    |> build_message()
    |> send_message()
  end

  def process_all_objects() do
    (Hexdocs.Store.list(:repo_bucket, "docs/") ++ Hexdocs.Store.list(:repo_bucket, "repos/"))
    |> Enum.shuffle()
    |> batched_send()
  end

  defp build_message(key) do
    %{
      "Records" => [%{"eventName" => "ObjectCreated:Put", "s3" => %{"object" => %{"key" => key}}}]
    }
  end

  def batched_send(keys) do
    keys
    |> Stream.filter(&Regex.match?(@key_regex, &1))
    |> Stream.map(&build_message/1)
    |> Task.async_stream(&send_message/1, max_concurrency: 10, ordered: false, timeout: 60_000)
    |> Stream.run()
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
end
