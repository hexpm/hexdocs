defmodule Hexdocs.Search do
  @type package :: String.t()
  @type version :: Version.t()
  @type search_items :: [map]

  @callback index(package, version, search_items) :: :ok

  defp impl, do: Application.fetch_env!(:hexdocs, :search_impl)

  @spec index(package, version, search_items) :: :ok
  def index(package, version, search_items) do
    impl().index(package, version, search_items)
  end
end
