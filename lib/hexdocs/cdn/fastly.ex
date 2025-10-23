defmodule Hexdocs.CDN.Fastly do
  @behaviour Hexdocs.CDN
  @fastly_url "https://api.fastly.com/"
  @fastly_purge_wait 4000

  def purge_key(service, keys) do
    keys = keys |> List.wrap() |> Enum.uniq()
    body = %{"surrogate_keys" => keys}
    service_id = Application.get_env(:hexdocs, service)
    sleep_time = div(Application.get_env(:hexdocs, :fastly_purge_wait, @fastly_purge_wait), 2)

    {:ok, 200, _, _} = post("service/#{service_id}/purge", body)

    Task.Supervisor.start_child(Hexdocs.Tasks, fn ->
      Process.sleep(sleep_time)
      {:ok, 200, _, _} = post("service/#{service_id}/purge", body)
      Process.sleep(sleep_time)
      {:ok, 200, _, _} = post("service/#{service_id}/purge", body)
    end)

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

    body = JSON.encode!(body)

    Hexdocs.HTTP.retry("fastly", url, fn -> :hackney.post(url, headers, body, []) end)
    |> read_body()
  end

  defp read_body({:ok, status, headers, client}) do
    {:ok, body} = :hackney.body(client)

    body =
      case JSON.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    {:ok, status, headers, body}
  end
end
