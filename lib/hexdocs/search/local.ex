defmodule Hexdocs.Search.Local do
  @behaviour Hexdocs.Search

  @impl true
  def index(_package, _version, _items), do: :ok
end
