defmodule Hexdocs.HexRepo do
  @callback get_names() :: {:ok, [binary()]} | {:error, term()}

  @module Application.fetch_env!(:hexdocs, :hex_repo_impl)

  defdelegate get_names(), to: @module
end

defmodule Hexdocs.HexRepo.HTTP do
  require Logger

  def get_names do
    case :hex_repo.get_names(:hex_core.default_config()) do
      {:ok, {200, _, body}} ->
        %{repository: "hexpm", packages: packages} = body
        names = for package <- packages, do: package.name
        {:ok, names}

      {:ok, {status, _headers, body}} ->
        message = """
        unexpected HTTP #{status}

        #{body}\
        """

        {:error, message}

      {:error, _reason} = error ->
        error
    end
  end
end
