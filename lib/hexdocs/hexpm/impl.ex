defmodule Hexdocs.Hexpm.Impl do
  @behaviour Hexdocs.Hexpm

  @refresh_errors [
    "invalid API key",
    "API key revoked",
    "key not authorized for this action"
  ]

  def verify_key(key, organization) do
    url = url("/api/auth?domain=docs&resource=#{organization}")
    fun = fn -> Hexdocs.HTTP.get(url, headers(key)) end

    case Hexdocs.HTTP.retry("hexpm", url, fun) do
      {:ok, status, _headers, _body} when status in 200..299 ->
        :ok

      {:ok, status, _headers, body} when status in [401, 403] ->
        body = JSON.decode!(body)

        if body["message"] in @refresh_errors do
          :refresh
        else
          {:error, body["message"]}
        end
    end
  end

  def get_package(repo, package) do
    key = Application.get_env(:hexdocs, :hexpm_secret)
    url = url("/api/repos/#{repo}/packages/#{package}")

    result =
      Hexdocs.HTTP.retry("hexpm", url, fn ->
        Hexdocs.HTTP.get(url, headers(key))
      end)

    case result do
      {:ok, 200, _headers, body} -> JSON.decode!(body)
      {:ok, 404, _headers, _body} -> nil
    end
  end

  def hexdocs_sitemap() do
    url = url("/docs_sitemap.xml")

    {:ok, 200, _headers, body} =
      Hexdocs.HTTP.retry("hexpm", url, fn ->
        Hexdocs.HTTP.get(url, [])
      end)

    body
  end

  defp url(path) do
    Application.get_env(:hexdocs, :hexpm_url) <> path
  end

  defp headers(key_or_token) do
    # Support both legacy API keys and OAuth Bearer tokens
    # OAuth tokens are JWTs that start with "eyJ" (base64 of '{"')
    # Legacy API keys are shorter hex strings
    authorization =
      if String.starts_with?(key_or_token, "eyJ") do
        "Bearer #{key_or_token}"
      else
        key_or_token
      end

    [
      {"accept", "application/json"},
      {"authorization", authorization}
    ]
  end
end
