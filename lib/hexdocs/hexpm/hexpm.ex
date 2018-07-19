defmodule HexDocs.Hexpm do
  @callback verify_key(key :: String.t(), organization :: String.t()) ::
              :ok | :refresh | {:error, reason :: String.t()}
  @callback get_package(repo :: String.t(), package :: String.t()) :: map()

  defp impl(), do: Application.get_env(:hexdocs, :hexpm_impl)

  def verify_key(key, organization), do: impl().verify_key(key, organization)
  def get_package(repo, package), do: impl().get_package(repo, package)
end
