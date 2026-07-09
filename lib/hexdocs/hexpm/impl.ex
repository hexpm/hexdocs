defmodule Hexdocs.Hexpm.Impl do
  @behaviour Hexdocs.Hexpm

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

  defp headers(key) do
    [
      {"accept", "application/json"},
      {"authorization", key}
    ]
  end
end
