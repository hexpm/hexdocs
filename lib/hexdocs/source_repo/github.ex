defmodule Hexdocs.SourceRepo.GitHub do
  @behaviour Hexdocs.SourceRepo
  @github_url "https://api.github.com"

  @impl true
  def versions(repo) do
    user = Application.get_env(:hexdocs, :github_user)
    token = Application.get_env(:hexdocs, :github_token)
    url = @github_url <> "/repos/#{repo}/tags"

    headers = [
      accept: "application/json"
    ]

    options = [
      :with_body,
      basic_auth: {user, token}
    ]

    Hexdocs.HTTP.retry("github", url, fn ->
      :hackney.get(url, headers, "", options)
    end)
    |> case do
      {:ok, 200, _headers, body} ->
        versions =
          for %{"name" => "v" <> version} <- Jason.decode!(body),
              not String.ends_with?(version, "-latest") do
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
