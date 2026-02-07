defmodule Hexdocs.HTTPTest do
  use ExUnit.Case, async: true

  defmodule StreamingPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn = send_chunked(conn, 200)
      {:ok, conn} = chunk(conn, "chunk1")
      {:ok, conn} = chunk(conn, "chunk2")
      {:ok, conn} = chunk(conn, "chunk3")
      conn
    end
  end

  setup do
    start_supervised!({Plug.Cowboy, plug: StreamingPlug, scheme: :http, port: 0})
    {:ok, port: :ranch.get_port(StreamingPlug.HTTP)}
  end

  describe "get_stream/2" do
    test "streams response body in chunks", %{port: port} do
      {:ok, status, _headers, stream} =
        Hexdocs.HTTP.get_stream("http://localhost:#{port}/", [])

      assert status == 200

      chunks =
        stream
        |> Enum.map(fn {:ok, chunk} -> chunk end)
        |> Enum.join()

      assert chunks == "chunk1chunk2chunk3"
    end
  end
end
