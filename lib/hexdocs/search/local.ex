defmodule Hexdocs.Search.Local do
  @behaviour Hexdocs.Search

  @impl true
  def index(_package, _version, _proglang, _items), do: :ok

  @impl true
  def delete(_package, _version), do: :ok
end
