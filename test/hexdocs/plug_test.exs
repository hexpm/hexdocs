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

  describe "OAuth flow" do
    test "redirect to OAuth authorize with no session" do
      conn = conn(:get, "http://plugtest.localhost:5002/foo") |> call()
      assert conn.status == 302

      [location] = get_resp_header(conn, "location")
      assert String.starts_with?(location, "http://localhost:5000/oauth/authorize?")

      uri = URI.parse(location)
      query = URI.decode_query(uri.query)

      assert query["response_type"] == "code"
      assert query["client_id"] == "hexdocs"
      assert query["scope"] == "docs:plugtest"
      assert query["code_challenge_method"] == "S256"
      assert query["state"] != nil
      assert query["code_challenge"] != nil

      # Should store PKCE verifier and state in session
      assert get_session(conn, "oauth_code_verifier") != nil
      assert get_session(conn, "oauth_state") != nil
      assert get_session(conn, "oauth_return_path") == "/foo"
    end

    test "OAuth callback with invalid state returns error" do
      conn =
        conn(:get, "http://plugtest.localhost:5002/oauth/callback?code=abc&state=wrong")
        |> init_test_session(%{
          "oauth_state" => "correct_state",
          "oauth_code_verifier" => "verifier"
        })
        |> call()

      assert conn.status == 403
      assert conn.resp_body =~ "Invalid OAuth state"
    end

    test "OAuth callback with missing code returns error" do
      conn =
        conn(:get, "http://plugtest.localhost:5002/oauth/callback?state=correct_state")
        |> init_test_session(%{
          "oauth_state" => "correct_state",
          "oauth_code_verifier" => "verifier"
        })
        |> call()

      assert conn.status == 400
      assert conn.resp_body =~ "Missing authorization code"
    end

    test "OAuth callback with error parameter returns error" do
      conn =
        conn(
          :get,
          "http://plugtest.localhost:5002/oauth/callback?error=access_denied&error_description=User%20denied"
        )
        |> init_test_session(%{"oauth_state" => "state", "oauth_code_verifier" => "verifier"})
        |> call()

      assert conn.status == 403
      assert conn.resp_body =~ "User denied"
    end

    test "serve page with valid OAuth token", %{test: test} do
      Mox.expect(HexpmMock, :verify_key, fn token, organization ->
        assert String.starts_with?(token, "eyJ")
        assert organization == "plugtest"
        :ok
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)
      Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}/index.html")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "body"
    end

    test "redirect to OAuth when token expired and no refresh token" do
      now = NaiveDateTime.utc_now()
      expired = NaiveDateTime.add(now, -1800, :second)

      conn =
        conn(:get, "http://plugtest.localhost:5002/foo")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "token_expires_at" => expired,
          "token_created_at" => NaiveDateTime.add(expired, -1800, :second)
        })
        |> call()

      assert conn.status == 302
      [location] = get_resp_header(conn, "location")
      assert String.starts_with?(location, "http://localhost:5000/oauth/authorize?")
    end
  end

  describe "page serving with OAuth" do
    test "serve 200 page", %{test: test} do
      Mox.expect(HexpmMock, :verify_key, fn token, organization ->
        assert String.starts_with?(token, "eyJ")
        assert organization == "plugtest"
        :ok
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)
      Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}/index.html")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "body"
    end

    test "serve 404 page", %{test: test} do
      Mox.expect(HexpmMock, :verify_key, fn token, organization ->
        assert String.starts_with?(token, "eyJ")
        assert organization == "plugtest"
        :ok
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)
      Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}/404.html")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 404
      assert conn.resp_body =~ "Page not found"
    end

    test "redirect to root", %{test: test} do
      Mox.expect(HexpmMock, :verify_key, fn token, organization ->
        assert String.starts_with?(token, "eyJ")
        assert organization == "plugtest"
        :ok
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)
      Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/#{test}/"]
    end

    test "serve index.html for root requests", %{test: test} do
      Mox.expect(HexpmMock, :verify_key, fn token, organization ->
        assert String.starts_with?(token, "eyJ")
        assert organization == "plugtest"
        :ok
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)
      Store.put!(@bucket, "plugtest/#{test}/index.html", "body")

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}/")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "body"
    end

    test "serve docs_config.js for unversioned and versioned requests", %{test: test} do
      Mox.expect(HexpmMock, :verify_key, 2, fn token, organization ->
        assert String.starts_with?(token, "eyJ")
        assert organization == "plugtest"
        :ok
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)
      Store.put!(@bucket, "plugtest/#{test}/docs_config.js", "var versionNodes;")

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}/docs_config.js")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "var versionNodes;"

      conn =
        conn(:get, "http://plugtest.localhost:5002/#{test}/1.0.0/docs_config.js")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 200
      assert conn.resp_body == "var versionNodes;"
    end

    test "token verification fails redirects to OAuth" do
      Mox.expect(HexpmMock, :verify_key, fn _token, _organization ->
        {:error, "account not authorized"}
      end)

      now = NaiveDateTime.utc_now()
      expires_at = NaiveDateTime.add(now, 1800, :second)

      conn =
        conn(:get, "http://plugtest.localhost:5002/foo")
        |> init_test_session(%{
          "access_token" => "eyJhbGciOiJFUzI1NiJ9.test",
          "refresh_token" => "eyJhbGciOiJFUzI1NiJ9.refresh",
          "token_expires_at" => expires_at,
          "token_created_at" => now
        })
        |> call()

      assert conn.status == 403
      assert conn.resp_body =~ "account not authorized"
    end

    test "handle no path redirects to OAuth" do
      conn = conn(:get, "http://plugtest.localhost:5002/") |> call()
      assert conn.status == 302

      [location] = get_resp_header(conn, "location")
      assert String.starts_with?(location, "http://localhost:5000/oauth/authorize?")
    end
  end

  defp call(conn) do
    Hexdocs.Plug.call(conn, [])
  end
end
