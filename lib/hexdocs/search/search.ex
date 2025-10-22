defmodule Hexdocs.Search do
  require Logger

  @type package :: String.t()
  @type version :: Version.t()
  @type proglang :: String.t()
  @type search_items :: [map]

  @callback index(package, version, proglang, search_items) :: :ok
  @callback delete(package, version) :: :ok

  defp impl, do: Application.fetch_env!(:hexdocs, :search_impl)

  @spec index(package, version, proglang, search_items) :: :ok
  def index(package, version, proglang, search_items) do
    impl().index(package, version, proglang, search_items)
  end

  @spec delete(package, version) :: :ok
  def delete(package, version) do
    impl().delete(package, version)
  end

  @spec find_search_items(package, version, [{Path.t(), content :: iodata}]) ::
          {proglang, search_items} | nil
  def find_search_items(package, version, files) do
    search_data_js =
      Enum.find_value(files, fn {path, content} ->
        case Path.basename(path) do
          "search_data-" <> _digest -> content
          _other -> nil
        end
      end)

    unless search_data_js do
      Logger.info("Failed to find search data for #{package} #{version}")
    end

    search_data_json =
      case search_data_js do
        "searchData=" <> json ->
          json

        _ when is_binary(search_data_js) ->
          raise "Unexpected search_data format for #{package} #{version}"

        nil ->
          nil
      end

    search_data =
      if search_data_json do
        try do
          :json.decode(search_data_json)
        catch
          _kind, reason ->
            raise "Failed to decode search data json for #{package} #{version}: #{inspect(reason)}"
        end
      end

    case search_data do
      %{"items" => [_ | _] = search_items} ->
        proglang = Map.get(search_data, "proglang") || proglang(search_items)
        {proglang, search_items}

      nil ->
        nil

      _ ->
        raise "Failed to extract search items and proglang from search data for #{package} #{version}"
    end
  end

  defp proglang(search_items) do
    if Enum.any?(search_items, &elixir_module?/1), do: "elixir", else: "erlang"
  end

  defp elixir_module?(%{"type" => "module", "title" => <<first_letter, _::binary>>})
       when first_letter in ?A..?Z,
       do: true

  defp elixir_module?(_), do: false
end
