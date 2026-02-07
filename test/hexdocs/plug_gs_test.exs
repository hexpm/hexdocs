defmodule Hexdocs.PlugGSTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  import Mox

  def fake_gs_auth, do: [{"authorization", "Bearer fake-token"}]

  # Mock GCS server that supports streaming
  defmodule MockGCSPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      case {conn.method, conn.path_info} do
        {"GET", ["hexdocs-private-test" | rest]} ->
          serve_file(conn, decode_path(rest))

        {"HEAD", ["hexdocs-private-test" | rest]} ->
          head_file(conn, decode_path(rest))

        {"PUT", ["hexdocs-private-test" | rest]} ->
          put_file(conn, decode_path(rest))

        {"DELETE", ["hexdocs-private-test" | rest]} ->
          delete_file(conn, decode_path(rest))

        _ ->
          send_resp(conn, 404, "Not Found")
      end
    end

    defp decode_path(segments) do
      segments
      |> Enum.map(&URI.decode/1)
      |> Enum.join("/")
    end

    defp serve_file(conn, path) do
      case :ets.lookup(:mock_gcs_files, path) do
        [{^path, content}] ->
          # Stream the content in chunks to test streaming
          conn = send_chunked(conn, 200)

          content
          |> chunk_binary(100)
          |> Enum.reduce(conn, fn chunk, conn ->
            {:ok, conn} = chunk(conn, chunk)
            conn
          end)

        [] ->
          send_resp(conn, 404, "Not Found")
      end
    end

    defp head_file(conn, path) do
      case :ets.lookup(:mock_gcs_files, path) do
        [{^path, _content}] -> send_resp(conn, 200, "")
        [] -> send_resp(conn, 404, "")
      end
    end

    defp put_file(conn, path) do
      {:ok, body, conn} = read_body(conn)
      :ets.insert(:mock_gcs_files, {path, body})
      send_resp(conn, 200, "")
    end

    defp delete_file(conn, path) do
      :ets.delete(:mock_gcs_files, path)
      send_resp(conn, 204, "")
    end

    defp chunk_binary(binary, chunk_size) do
      binary
      |> :binary.bin_to_list()
      |> Enum.chunk_every(chunk_size)
      |> Enum.map(&:binary.list_to_bin/1)
    end
  end

  setup do
    # Create ETS table for mock file storage
    if :ets.whereis(:mock_gcs_files) == :undefined do
      :ets.new(:mock_gcs_files, [:named_table, :public, :set])
    end

    :ets.delete_all_objects(:mock_gcs_files)

    # Start mock GCS server
    port = Enum.random(50_000..60_000)
    start_supervised!({Plug.Cowboy, plug: MockGCSPlug, scheme: :http, port: port})

    # Configure to use GS store with mock server
    original_store_impl = Application.get_env(:hexdocs, :store_impl)
    original_gs_url = Application.get_env(:hexdocs, :gs_url)
    original_gs_auth = Application.get_env(:hexdocs, :gs_auth)
    original_bucket = Application.get_env(:hexdocs, :docs_private_bucket)

    Application.put_env(:hexdocs, :store_impl, Hexdocs.Store.Impl)
    Application.put_env(:hexdocs, :gs_url, "http://localhost:#{port}")
    Application.put_env(:hexdocs, :gs_auth, {__MODULE__, :fake_gs_auth})

    Application.put_env(:hexdocs, :docs_private_bucket,
      name: "hexdocs-private-test",
      implementation: Hexdocs.Store.GS
    )

    on_exit(fn ->
      Application.put_env(:hexdocs, :store_impl, original_store_impl)

      if original_gs_url do
        Application.put_env(:hexdocs, :gs_url, original_gs_url)
      else
        Application.delete_env(:hexdocs, :gs_url)
      end

      if original_gs_auth do
        Application.put_env(:hexdocs, :gs_auth, original_gs_auth)
      else
        Application.delete_env(:hexdocs, :gs_auth)
      end

      Application.put_env(:hexdocs, :docs_private_bucket, original_bucket)
    end)

    {:ok, port: port}
  end

  setup :verify_on_exit!

  describe "streaming through plug with GS store" do
    test "streams page content from GCS", %{test: test} do
      # Set up mock expectations
      Mox.expect(Hexdocs.HexpmMock, :verify_key, fn _token, _org -> :ok end)

      # Store a file in mock GCS
      content = String.duplicate("Hello from GCS! ", 100)
      path = "gstest/#{test}/index.html"
      :ets.insert(:mock_gcs_files, {path, content})

      # Make request through the plug
      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)

      conn =
        conn(:get, "http://gstest.localhost:5002/#{test}/index.html")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == content
    end

    test "streams large file in chunks", %{test: test} do
      Mox.expect(Hexdocs.HexpmMock, :verify_key, fn _token, _org -> :ok end)

      # Create a larger file to ensure chunking works
      content = :crypto.strong_rand_bytes(5000) |> Base.encode64()
      path = "gstest/#{test}/large.html"
      :ets.insert(:mock_gcs_files, {path, content})

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)

      conn =
        conn(:get, "http://gstest.localhost:5002/#{test}/large.html")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == content
    end

    test "returns 404 for missing file", %{test: test} do
      Mox.expect(Hexdocs.HexpmMock, :verify_key, fn _token, _org -> :ok end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)

      conn =
        conn(:get, "http://gstest.localhost:5002/#{test}/nonexistent.html")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 404
    end
  end

  defp call(conn) do
    Hexdocs.Plug.call(conn, Hexdocs.Plug.init([]))
  end
end
