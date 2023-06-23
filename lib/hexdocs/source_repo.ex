defmodule Hexdocs.SourceRepo do
  @callback versions(repo :: String.t()) :: {:ok, [Version.t()]} | {:error, term()}

  def versions!(repo) do
    case versions(repo) do
      {:ok, versions} -> versions
      {:error, exception} -> raise exception
    end
  end

  def versions(repo) do
    impl().versions(repo)
  end

  defp impl do
    Application.fetch_env!(:hexdocs, :source_repo_impl)
  end
end
