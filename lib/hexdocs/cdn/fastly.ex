defmodule Hexdocs.CDN.Fastly do
  @behaviour Hexdocs.CDN
  @fastly_url "https://api.fastly.com/"

  def purge_key(service, keys) do
    keys = keys |> List.wrap() |> Enum.uniq()
    body = %{"surrogate_keys" => keys}
    service_id = Application.get_env(:hexdocs, service)

    {:ok, 200, _, _} = post("service/#{service_id}/purge", body)
    :ok
  end

  defp auth() do
    Application.get_env(:hexdocs, :fastly_key)
  end

  defp post(url, body) do
    url = @fastly_url <> url

    headers = [
      "fastly-key": auth(),
      accept: "application/json",
      "content-type": "application/json"
    ]

    body = Jason.encode!(body)

    fn -> :hackney.post(url, headers, body, []) end
    |> Hexdocs.HTTP.retry("fastly")
    |> read_body()
  end

  defp read_body({:ok, status, headers, client}) do
    {:ok, body} = :hackney.body(client)

    body =
      case Jason.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    {:ok, status, headers, body}
  end
end
