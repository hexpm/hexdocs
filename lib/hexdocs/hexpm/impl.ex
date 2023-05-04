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
        body = Jason.decode!(body)

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
      {:ok, 200, _headers, body} -> Jason.decode!(body)
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

  defp headers(key) do
    [
      {"accept", "application/json"},
      {"authorization", key}
    ]
  end
end
