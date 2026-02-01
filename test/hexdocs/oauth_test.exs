defmodule Hexdocs.OAuthTest do
  use ExUnit.Case, async: true

  alias Hexdocs.OAuth

  describe "generate_code_verifier/0" do
    test "generates a non-empty string" do
      verifier = OAuth.generate_code_verifier()

      assert is_binary(verifier)
      assert String.length(verifier) > 0
    end

    test "generates unique values" do
      verifier1 = OAuth.generate_code_verifier()
      verifier2 = OAuth.generate_code_verifier()

      assert verifier1 != verifier2
    end

    test "generates URL-safe base64 encoded string" do
      verifier = OAuth.generate_code_verifier()

      # Should not contain URL-unsafe characters
      refute String.contains?(verifier, "+")
      refute String.contains?(verifier, "/")
      refute String.contains?(verifier, "=")
    end

    test "generates 43-character string (32 bytes base64url encoded)" do
      verifier = OAuth.generate_code_verifier()

      # 32 bytes base64url encoded without padding = 43 characters
      assert String.length(verifier) == 43
    end
  end

  describe "generate_code_challenge/1" do
    test "generates a non-empty string" do
      verifier = OAuth.generate_code_verifier()
      challenge = OAuth.generate_code_challenge(verifier)

      assert is_binary(challenge)
      assert String.length(challenge) > 0
    end

    test "generates URL-safe base64 encoded string" do
      verifier = OAuth.generate_code_verifier()
      challenge = OAuth.generate_code_challenge(verifier)

      refute String.contains?(challenge, "+")
      refute String.contains?(challenge, "/")
      refute String.contains?(challenge, "=")
    end

    test "produces consistent output for same input" do
      verifier = OAuth.generate_code_verifier()
      challenge1 = OAuth.generate_code_challenge(verifier)
      challenge2 = OAuth.generate_code_challenge(verifier)

      assert challenge1 == challenge2
    end

    test "produces different output for different inputs" do
      verifier1 = OAuth.generate_code_verifier()
      verifier2 = OAuth.generate_code_verifier()

      challenge1 = OAuth.generate_code_challenge(verifier1)
      challenge2 = OAuth.generate_code_challenge(verifier2)

      assert challenge1 != challenge2
    end

    test "produces correct SHA-256 hash" do
      # Known test vector
      verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

      expected_challenge =
        :crypto.hash(:sha256, verifier)
        |> Base.url_encode64(padding: false)

      assert OAuth.generate_code_challenge(verifier) == expected_challenge
    end
  end

  describe "generate_state/0" do
    test "generates a non-empty string" do
      state = OAuth.generate_state()

      assert is_binary(state)
      assert String.length(state) > 0
    end

    test "generates unique values" do
      state1 = OAuth.generate_state()
      state2 = OAuth.generate_state()

      assert state1 != state2
    end
  end

  describe "authorization_url/1" do
    test "builds correct authorization URL" do
      url =
        OAuth.authorization_url(
          hexpm_url: "https://hex.pm",
          client_id: "hexdocs",
          redirect_uri: "https://acme.hexdocs.pm/oauth/callback",
          scope: "docs:acme",
          state: "random_state",
          code_challenge: "challenge123"
        )

      assert String.starts_with?(url, "https://hex.pm/oauth/authorize?")

      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert query["response_type"] == "code"
      assert query["client_id"] == "hexdocs"
      assert query["redirect_uri"] == "https://acme.hexdocs.pm/oauth/callback"
      assert query["scope"] == "docs:acme"
      assert query["state"] == "random_state"
      assert query["code_challenge"] == "challenge123"
      assert query["code_challenge_method"] == "S256"
    end

    test "properly encodes special characters in parameters" do
      url =
        OAuth.authorization_url(
          hexpm_url: "https://hex.pm",
          client_id: "client with spaces",
          redirect_uri: "https://example.com/callback?foo=bar",
          scope: "docs:org",
          state: "state&with=special",
          code_challenge: "abc123"
        )

      # URL should be properly encoded
      assert String.contains?(url, "client+with+spaces") or
               String.contains?(url, "client%20with%20spaces")
    end
  end

  describe "config/0" do
    test "returns keyword list with expected keys" do
      config = OAuth.config()

      assert Keyword.has_key?(config, :hexpm_url)
      assert Keyword.has_key?(config, :client_id)
      assert Keyword.has_key?(config, :client_secret)
    end
  end
end
