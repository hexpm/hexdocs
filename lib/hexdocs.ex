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

  # TODO: remove after running on production
  def process_all_sitemaps(paths) do
    paths
    |> Stream.map(&%{"hexdocs:sitemap" => &1})
    |> Task.async_stream(&send_message/1, max_concurrency: 10, ordered: false)
    |> Stream.run()
  end

  # TODO: remove after running on production
  def paths_for_sitemaps() do
    Hexdocs.Store.list(:repo_bucket, "docs/")
    |> Stream.filter(&Regex.match?(@key_regex, &1))
    |> Stream.map(fn path ->
      {package, version} = filename_to_release(path)
      {path, package, Version.parse!(version)}
    end)
    |> Stream.chunk_by(fn {_, package, _} -> package end)
    |> Stream.flat_map(fn entries ->
      entries = Enum.sort_by(entries, fn {_, _, version} -> version end, {:desc, Version})
      all_versions = for {_, _, version} <- entries, do: version

      List.wrap(
        Enum.find_value(entries, fn {path, _, version} ->
          Hexdocs.Utils.latest_version?(version, all_versions) && path
        end)
      )
    end)
  end

  defp filename_to_release(file) do
    base = Path.basename(file, ".tar.gz")
    [package, version] = String.split(base, "-", parts: 2)
    {package, version}
  end
end
