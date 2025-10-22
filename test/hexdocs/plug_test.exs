defmodule Hexdocs.PlugTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  import Mox
  alias Hexdocs.{HexpmMock, Store}

  setup :verify_on_exit!

  @bucket :docs_private_bucket

  test "requests without subdomain not supported" do
    conn = conn(:get, "http://localhost:5002/foo") |> call()
    assert conn.status == 400
  end

  test "redirect to hexpm with no session and no key" do
    conn = conn(:get, "http://plugtest.localhost:5002/foo") |> call()
    assert conn.status == 302

    assert get_resp_header(conn, "location") ==
             ["http://localhost:5000/login?hexdocs=plugtest&return=/foo"]
  end

  test "handle no path" do
    conn = conn(:get, "http://plugtest.localhost:5002/") |> call()
    assert conn.status == 302

    assert get_resp_header(conn, "location") ==
             ["http://localhost:5000/login?hexdocs=plugtest&return=/"]
  end

  test "update session and redirect when key is set" do
    conn = conn(:get, "http://plugtest.localhost:5002/foo?key=abc") |> call()
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["/foo"]

    assert get_session(conn, "key") == "abc"
    assert recent?(get_session(conn, "key_refreshed_at"))
    assert recent?(get_session(conn, "key_created_at"))
  end

  test "redirect to hexpm with dead key" do
    old = ~N[2018-01-01 00:00:00]

    conn =
      conn(:get, "http://plugtest.localhost:5002/foo")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => old, "key_created_at" => old})
      |> call()

    assert conn.status == 302

    assert get_resp_header(conn, "location") ==
             ["http://localhost:5000/login?hexdocs=plugtest&return=/foo"]
  end

  test "reverify stale key succeeds", %{test: test} do
    Mox.expect(HexpmMock, :verify_key, fn key, organization ->
      assert key == "abc"
      assert organization == "plugtest"
      :ok
    end)

    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
    Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}/index.html")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => old, "key_created_at" => old})
      |> call()

    assert conn.status == 200
    assert conn.resp_body == "body"
  end

  test "reverify stale key requires refresh and redirects", %{test: test} do
    Mox.expect(HexpmMock, :verify_key, fn key, organization ->
      assert key == "abc"
      assert organization == "plugtest"
      :refresh
    end)

    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
    Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

    conn =
      conn(:get, "http://plugtest.localhost:5002/foo")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => old, "key_created_at" => old})
      |> call()

    assert conn.status == 302

    assert get_resp_header(conn, "location") ==
             ["http://localhost:5000/login?hexdocs=plugtest&return=/foo"]
  end

  test "reverify stale key fails" do
    Mox.expect(HexpmMock, :verify_key, fn key, organization ->
      assert key == "abc"
      assert organization == "plugtest"
      {:error, "account not authorized"}
    end)

    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)

    conn =
      conn(:get, "http://plugtest.localhost:5002/foo")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => old, "key_created_at" => old})
      |> call()

    assert conn.status == 403
    assert conn.resp_body =~ "account not authorized"
  end

  test "serve 200 page", %{test: test} do
    now = NaiveDateTime.utc_now()
    Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}/index.html")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => now, "key_created_at" => now})
      |> call()

    assert conn.status == 200
    assert conn.resp_body == "body"
  end

  test "serve 404 page", %{test: test} do
    now = NaiveDateTime.utc_now()
    Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}/404.html")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => now, "key_created_at" => now})
      |> call()

    assert conn.status == 404
    assert conn.resp_body =~ "Page not found"
  end

  test "redirect to root", %{test: test} do
    now = NaiveDateTime.utc_now()
    Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => now, "key_created_at" => now})
      |> call()

    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["/#{test}/"]
  end

  test "serve index.html for root requests", %{test: test} do
    now = NaiveDateTime.utc_now()
    Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}/")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => now, "key_created_at" => now})
      |> call()

    assert conn.status == 200
    assert conn.resp_body == "body"
  end

  test "serve docs_config.js for unversioned and versioned requests", %{test: test} do
    now = NaiveDateTime.utc_now()
    Store.put!(@bucket, "plugtest/#{test}/docs_config.js", "var versionNodes;")

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}/docs_config.js")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => now, "key_created_at" => now})
      |> call()

    assert conn.status == 200
    assert conn.resp_body == "var versionNodes;"

    conn =
      conn(:get, "http://plugtest.localhost:5002/#{test}/1.0.0/docs_config.js")
      |> init_test_session(%{"key" => "abc", "key_refreshed_at" => now, "key_created_at" => now})
      |> call()

    assert conn.status == 200
    assert conn.resp_body == "var versionNodes;"
  end

  defp call(conn) do
    Hexdocs.Plug.call(conn, [])
  end

  defp recent?(datetime) do
    abs(NaiveDateTime.diff(datetime, NaiveDateTime.utc_now())) < 3
  end
end
