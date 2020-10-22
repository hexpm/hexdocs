defmodule Hexdocs do
  @key_regex ~r"docs/(.*)-(.*).tar.gz$"

  def process_object(key) do
    key
    |> build_message()
    |> send_message()
  end

  def process_all_objects() do
    batched_send(Hexdocs.Store.list(:repo_bucket, "docs/"))
    batched_send(Hexdocs.Store.list(:repo_bucket, "repos/"))
  end

  defp build_message(key) do
    %{
      "Records" => [%{"eventName" => "ObjectCreated:Put", "s3" => %{"object" => %{"key" => key}}}]
    }
  end

  defp batched_send(keys) do
    keys
    |> Stream.filter(&Regex.match?(@key_regex, &1))
    |> Stream.map(&build_message/1)
    |> Task.async_stream(&send_message/1, max_concurrency: 10, ordered: false)
    |> Stream.run()
  end

  defp send_message(map) do
    queue = Application.fetch_env!(:hexdocs, :queue_id)
    message = Jason.encode!(map)

    ExAws.SQS.send_message(queue, message)
    |> ExAws.request!()
  end

  def url(repository, path) do
    "/" <> _ = path
    host = Application.get_env(:hexdocs, :host)
    scheme = if host == "hexdocs.pm", do: "https", else: "http"
    subdomain = if repository == "hexpm", do: "", else: "#{repository}."
    "#{scheme}://#{subdomain}#{host}#{path}"
  end
end
