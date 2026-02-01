defmodule Hexdocs.OAuth do
  @moduledoc """
  OAuth 2.0 Authorization Code with PKCE client for hexdocs.

  This module implements the OAuth 2.0 Authorization Code flow with PKCE (Proof Key for
  Code Exchange) as defined in RFC 7636. It can be used by any application integrating
  with hexpm's OAuth infrastructure.

  ## Flow

  1. Generate code_verifier and code_challenge using `generate_code_verifier/0` and
     `generate_code_challenge/1`
  2. Build authorization URL with `authorization_url/1` and redirect user
  3. After user authorizes, exchange the code for tokens with `exchange_code/3`
  4. Use `refresh_token/2` to get new access tokens before expiration
  """

  @doc """
  Generate a cryptographically random code_verifier for PKCE.

  Returns a 43-character URL-safe base64 string (32 random bytes encoded).
  """
  def generate_code_verifier do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generate code_challenge from code_verifier using S256 method.

  Computes SHA-256 hash of the verifier and base64url encodes it.
  """
  def generate_code_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generate a random state parameter for CSRF protection.
  """
  def generate_state do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Build the OAuth authorization URL with PKCE parameters.

  ## Options (all required)

    * `:hexpm_url` - Base URL of hexpm (e.g., "https://hex.pm")
    * `:client_id` - OAuth client ID
    * `:redirect_uri` - URI to redirect to after authorization
    * `:scope` - Space-separated scopes to request
    * `:state` - Random state for CSRF protection
    * `:code_challenge` - PKCE code challenge

  """
  def authorization_url(opts) do
    hexpm_url = Keyword.fetch!(opts, :hexpm_url)
    client_id = Keyword.fetch!(opts, :client_id)
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)
    scope = Keyword.fetch!(opts, :scope)
    state = Keyword.fetch!(opts, :state)
    code_challenge = Keyword.fetch!(opts, :code_challenge)

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "scope" => scope,
        "state" => state,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      })

    "#{hexpm_url}/oauth/authorize?#{query}"
  end

  @doc """
  Exchange an authorization code for access and refresh tokens.

  ## Parameters

    * `code` - The authorization code received from the callback
    * `code_verifier` - The original code_verifier generated before authorization
    * `opts` - Keyword list with:
      * `:hexpm_url` - Base URL of hexpm
      * `:client_id` - OAuth client ID
      * `:client_secret` - OAuth client secret
      * `:redirect_uri` - The same redirect_uri used in authorization

  ## Returns

    * `{:ok, tokens}` - Map with "access_token", "refresh_token", "expires_in", etc.
    * `{:error, reason}` - Error tuple with status code and error response
  """
  def exchange_code(code, code_verifier, opts) do
    hexpm_url = Keyword.fetch!(opts, :hexpm_url)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)

    body =
      %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri,
        "client_id" => client_id,
        "client_secret" => client_secret,
        "code_verifier" => code_verifier
      }
      |> maybe_put("name", opts[:name])
      |> JSON.encode!()

    url = "#{hexpm_url}/api/oauth/token"
    headers = [{"content-type", "application/json"}]

    case Hexdocs.HTTP.post(url, headers, body) do
      {:ok, status, _headers, response_body} when status in 200..299 ->
        {:ok, JSON.decode!(response_body)}

      {:ok, status, _headers, response_body} ->
        {:error, {status, JSON.decode!(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refresh an access token using a refresh token.

  ## Parameters

    * `refresh_token` - The refresh token from a previous token response
    * `opts` - Keyword list with:
      * `:hexpm_url` - Base URL of hexpm
      * `:client_id` - OAuth client ID
      * `:client_secret` - OAuth client secret

  ## Returns

    * `{:ok, tokens}` - Map with new "access_token", "refresh_token", "expires_in", etc.
    * `{:error, reason}` - Error tuple
  """
  def refresh_token(refresh_token, opts) do
    hexpm_url = Keyword.fetch!(opts, :hexpm_url)
    client_id = Keyword.fetch!(opts, :client_id)
    client_secret = Keyword.fetch!(opts, :client_secret)

    body =
      JSON.encode!(%{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_id" => client_id,
        "client_secret" => client_secret
      })

    url = "#{hexpm_url}/api/oauth/token"
    headers = [{"content-type", "application/json"}]

    case Hexdocs.HTTP.post(url, headers, body) do
      {:ok, status, _headers, response_body} when status in 200..299 ->
        {:ok, JSON.decode!(response_body)}

      {:ok, status, _headers, response_body} ->
        {:error, {status, JSON.decode!(response_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the OAuth configuration from application environment.

  Returns a keyword list with all OAuth settings needed for API calls.
  """
  def config do
    [
      hexpm_url: Application.get_env(:hexdocs, :hexpm_url),
      client_id: Application.get_env(:hexdocs, :oauth_client_id),
      client_secret: Application.get_env(:hexdocs, :oauth_client_secret)
    ]
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
