defmodule Hexdocs.Search.Typesense do
  @moduledoc false
  require Logger
  alias Hexdocs.HTTP

  @behaviour Hexdocs.Search

  @impl true
  def index(package, version, proglang, search_items) do
    full_package = full_package(package, version)

    ndjson =
      Enum.map(search_items, fn item ->
        json =
          Map.take(item, ["type", "ref", "title", "doc"])
          |> Map.put("package", full_package)
          |> Map.put("proglang", proglang)
          |> :json.encode()

        [json, ?\n]
      end)

    url = url("collections/#{collection()}/documents/import?action=create")
    headers = [{"x-typesense-api-key", api_key()}]

    case HTTP.post(url, headers, ndjson, [:with_body]) do
      {:ok, 200, _resp_headers, ndjson} ->
        ndjson
        |> String.split("\n")
        |> Enum.each(fn json ->
          case :json.decode(json) do
            %{"success" => true} ->
              :ok

            %{"success" => false, "error" => error, "document" => document} ->
              raise "Failed to index search item for #{package} #{version} for document #{inspect(document)}: #{inspect(error)}"
          end
        end)

      {:ok, status, _resp_headers, _body} ->
        raise "Failed to index search items for #{package} #{version}: status=#{status}"

      {:error, reason} ->
        raise "Failed to index search items #{package} #{version}: #{inspect(reason)}"
    end
  end

  @impl true
  def delete(package, version) do
    full_package = full_package(package, version)

    query = URI.encode_query([{"filter_by", "package:#{full_package}"}])
    url = url("collections/#{collection()}/documents?" <> query)
    headers = [{"x-typesense-api-key", api_key()}]

    case HTTP.delete(url, headers) do
      {:ok, 200, _resp_headers, _body} ->
        :ok

      {:ok, status, _resp_headers, _body} ->
        raise "Failed to delete search items for #{package} #{version}: status=#{status}"

      {:error, reason} ->
        raise "Failed to delete search items for #{package} #{version}: #{inspect(reason)}"
    end
  end

  @spec collection :: String.t()
  def collection do
    Application.fetch_env!(:hexdocs, :typesense_collection)
  end

  @spec collection_schema :: map
  def collection_schema(collection \\ collection()) do
    %{
      "fields" => [
        %{"facet" => true, "name" => "proglang", "type" => "string"},
        %{"facet" => true, "name" => "type", "type" => "string"},
        %{
          "name" => "title",
          "type" => "string",
          "token_separators" => [".", "_", "-", "*", "`", ":", "@", "/"]
        },
        %{
          "name" => "doc",
          "type" => "string",
          "token_separators" => [".", "_", "-", "*", "`", ":", "@", "/"]
        },
        %{"facet" => true, "name" => "package", "type" => "string"}
      ],
      "name" => collection
    }
  end

  @spec api_key :: String.t()
  def api_key do
    Application.fetch_env!(:hexdocs, :typesense_api_key)
  end

  defp full_package(package, version) do
    "#{package}-#{version}"
  end

  defp url(path) do
    base_url = Application.fetch_env!(:hexdocs, :typesense_url)
    Path.join(base_url, path)
  end
end
