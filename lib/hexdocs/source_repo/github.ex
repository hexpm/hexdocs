defmodule Hexdocs.SourceRepo.GitHub do
  @behaviour Hexdocs.SourceRepo
  @github_url "https://api.github.com"

  @impl true
  def versions(repo) do
    url = @github_url <> "/repos/#{repo}/tags"

    headers = [
      accept: "application/json"
    ]

    options = [
      :with_body
    ]

    Hexdocs.HTTP.retry("github", url, fn ->
      :hackney.get(url, headers, "", options)
    end)
    |> case do
      {:ok, 200, _headers, body} ->
        versions =
          for tag <- Jason.decode!(body) do
            "v" <> version = tag["name"]
            Version.parse!(version)
          end

        {:ok, versions}

      {:ok, status, _headers, body} ->
        {:error, RuntimeError.exception("http unexpected status #{status}: #{body}")}

      {:error, reason} ->
        {:error, RuntimeError.exception("http error: #{inspect(reason)}")}
    end
  end
end
