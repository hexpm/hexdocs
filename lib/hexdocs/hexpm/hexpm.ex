defmodule Hexdocs.Hexpm do
  @callback get_package(repo :: String.t(), package :: String.t()) :: map() | nil
  @callback hexdocs_sitemap() :: binary()

  defp impl(), do: Application.get_env(:hexdocs, :hexpm_impl)

  def get_package(repo, package), do: impl().get_package(repo, package)
  def hexdocs_sitemap(), do: impl().hexdocs_sitemap()
end
