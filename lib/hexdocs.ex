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
    %{"Records" => [%{"eventName" => "ObjectCreated:Put", "s3" => %{"object" => %{"key" => key}}}]}
  end

  defp batched_send(keys) do
    keys
    |> Stream.filter(&Regex.match?(@key_regex, &1))
    |> Stream.map(&build_message/1)
    |> Stream.chunk_every(10, 10)
    |> Enum.each(&send_batch_messages/1)
  end

  defp send_batch_messages(maps) when length(maps) <= 10 do
    queue = Application.fetch_env!(:hexdocs, :queue_id)
    messages = Enum.map(maps, &Jason.encode!/1)

    ExAws.SQS.send_message_batch(queue, messages)
    |> ExAws.request()
  end

  defp send_message(map) do
    queue = Application.fetch_env!(:hexdocs, :queue_id)
    message = Jason.encode!(map)

    ExAws.SQS.send_message(queue, message)
    |> ExAws.request()
  end
end
