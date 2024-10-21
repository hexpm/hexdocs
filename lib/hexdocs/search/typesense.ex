defmodule Hexdocs.Search.Typesense do
  @moduledoc false
  require Logger
  alias Hexdocs.HTTP

  @behaviour Hexdocs.Search

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

    url = url("collections/#{collection()}/documents/import?action=create")
    headers = [{"x-typesense-api-key", api_key()}]

    case HTTP.post(url, headers, ndjson, [:with_body]) do
      {:ok, 200, _resp_headers, ndjson} ->
        ndjson
        |> String.split("\n")
        |> Enum.each(fn json ->
          case Jason.decode!(json) do
            %{"success" => true} ->
              :ok

            %{"success" => false, "error" => error, "document" => document} ->
              Logger.error(
                "Failed to index search item for #{package} #{version}: #{inspect(document)}: #{inspect(error)}"
              )
          end
        end)

      {:ok, status, _resp_headers, _body} ->
        Logger.error("Failed to index search items for #{package} #{version}: status=#{status}")

      {:error, reason} ->
        Logger.error("Failed to index search items #{package} #{version}: #{inspect(reason)}")
    end
  end

  @spec collection :: String.t()
  def collection do
    Application.fetch_env!(:hexdocs, :typesense_collection)
  end

  @spec api_key :: String.t()
  def api_key do
    Application.fetch_env!(:hexdocs, :typesense_api_key)
  end

  defp url(path) do
    base_url = Application.fetch_env!(:hexdocs, :typesense_url)
    Path.join(base_url, path)
  end
end
