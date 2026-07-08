defmodule Hexdocs.Store.GSTest do
  use ExUnit.Case, async: false

  def fake_gs_auth, do: [{"authorization", "Bearer fake-token"}]

  defmodule MockGCSPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      case {conn.method, conn.path_info} do
        {"DELETE", ["hexdocs-test" | rest]} ->
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

    defp delete_file(conn, path) do
      case :ets.lookup(:mock_gs_store_files, path) do
        [{^path, _content}] ->
          :ets.delete(:mock_gs_store_files, path)
          send_resp(conn, 204, "")

        [] ->
          body =
            "<?xml version='1.0' encoding='UTF-8'?>" <>
              "<Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message></Error>"

          conn
          |> put_resp_content_type("application/xml")
          |> send_resp(404, body)
      end
    end
  end

  setup do
    if :ets.whereis(:mock_gs_store_files) == :undefined do
      :ets.new(:mock_gs_store_files, [:named_table, :public, :set])
    end

    :ets.delete_all_objects(:mock_gs_store_files)

    pid = start_supervised!({Bandit, plug: MockGCSPlug, scheme: :http, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(pid)

    original_gs_url = Application.get_env(:hexdocs, :gs_url)
    original_gs_auth = Application.get_env(:hexdocs, :gs_auth)

    Application.put_env(:hexdocs, :gs_url, "http://localhost:#{port}")
    Application.put_env(:hexdocs, :gs_auth, {__MODULE__, :fake_gs_auth})

    on_exit(fn ->
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
    end)

    :ok
  end

  describe "delete_many/2" do
    test "deletes existing keys" do
      :ets.insert(:mock_gs_store_files, {"package/1.0.0/index.html", "contents"})
      :ets.insert(:mock_gs_store_files, {"package/docs_config.js", "contents"})

      assert :ok =
               Hexdocs.Store.GS.delete_many("hexdocs-test", [
                 "package/1.0.0/index.html",
                 "package/docs_config.js"
               ])

      assert :ets.lookup(:mock_gs_store_files, "package/1.0.0/index.html") == []
      assert :ets.lookup(:mock_gs_store_files, "package/docs_config.js") == []
    end

    test "tolerates keys that are already deleted" do
      :ets.insert(:mock_gs_store_files, {"package/1.0.0/index.html", "contents"})

      assert :ok =
               Hexdocs.Store.GS.delete_many("hexdocs-test", [
                 "package/1.0.0/index.html",
                 "package/docs_config.js"
               ])

      assert :ets.lookup(:mock_gs_store_files, "package/1.0.0/index.html") == []
    end
  end
end
