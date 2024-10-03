defmodule Hexdocs.Search.Typesense do
  require Logger

  @behaviour Hexdocs.Search

  @collection "hexdocs"

  @impl true
  def index(package, version, search_items) do
    full_package = "#{package}-#{version}"

    ndjson =
      Enum.map(search_items, fn item ->
        json =
          Map.take(item, ["type", "ref", "title", "doc"])
          |> Map.put("package", full_package)
          |> Jason.encode_to_iodata!()

        [json, ?\n]
      end)

    url = url("collections/#{@collection}/documents/import?action=create")
    headers = headers([{"content-type", "text/plain"}])

    case :hackney.post(url, headers, ndjson) do
      {:ok, 200, _resp_headers, ref} ->
        process_results(package, version, ref)
        :ok

      {:ok, status, _resp_headers, _ref} ->
        Logger.error("Failed to index search items for #{package} #{version}: status=#{status}")

      {:error, reason} ->
        Logger.error("Failed to index search items #{package} #{version}: #{inspect(reason)}")
    end
  end

  @spec process_results(String.t(), Version.t(), :hackney.client_ref()) :: :ok
  defp process_results(package, version, ref) do
    case :hackney.stream_body(ref) do
      {:ok, ndjson} ->
        ndjson
        |> String.splitter("\n")
        |> Stream.each(fn json ->
          case Jason.decode!(json) do
            %{"success" => true} ->
              :ok

            %{"success" => false, "error" => error, "document" => document} ->
              Logger.error(
                "Failed to index search item for #{package} #{version}: #{inspect(document)}: #{inspect(error)}"
              )
          end
        end)
        |> Stream.run()

      {:error, reason} ->
        Logger.error(
          "Failed to read results from indexing search items for #{package} #{version}: #{inspect(reason)}"
        )

      :done ->
        :ok
    end
  end

  defp url(path) do
    base_url = Application.fetch_env!(:hexdocs, :typesense_url)
    Path.join(base_url, path)
  end

  defp headers(headers) do
    api_key = Application.fetch_env!(:hexdocs, :typesense_api_key)
    [{"x-typesense-api-key", api_key} | headers]
  end
end
