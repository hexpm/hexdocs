defmodule Hexdocs.Plug.SSL do
  alias Plug.Conn

  def init(opts) do
    Plug.SSL.init(opts)
  end

  def call(%Conn{path_info: ["status"]} = conn, _opts) do
    conn
  end

  def call(conn, opts) do
    Plug.SSL.call(conn, opts)
  end
end
