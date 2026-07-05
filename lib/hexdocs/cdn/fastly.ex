defmodule Hexdocs.CDN.Fastly do
  @behaviour Hexdocs.CDN
  @fastly_url "https://api.fastly.com/"
  @fastly_purge_wait 4000

  def purge_key(service, keys) do
    keys = keys |> List.wrap() |> Enum.uniq()
    body = %{"surrogate_keys" => keys}
    service_id = Application.get_env(:hexdocs, service)
    sleep_time = div(Application.get_env(:hexdocs, :fastly_purge_wait, @fastly_purge_wait), 2)

    purge!(service, service_id, body)

    Task.Supervisor.start_child(Hexdocs.Tasks, fn ->
      Process.sleep(sleep_time)
      purge!(service, service_id, body)
      Process.sleep(sleep_time)
      purge!(service, service_id, body)
    end)

    :ok
  end

  defp purge!(service, service_id, body) do
    case post("service/#{service_id}/purge", body) do
      {:ok, 200, _headers, _body} ->
        :ok

      {:ok, status, _headers, body} ->
        raise "failed to purge #{service} (service id: #{service_id}), " <>
                "status: #{status}, body: #{inspect(body)}"
    end
  end

  defp auth() do
    Application.get_env(:hexdocs, :fastly_key)
  end

  defp post(url, body) do
    url = @fastly_url <> url

    headers = [
      {"fastly-key", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    body = JSON.encode!(body)

    Hexdocs.HTTP.retry("fastly", url, fn -> Hexdocs.HTTP.post(url, headers, body) end)
    |> decode_body()
  end

  defp decode_body({:ok, status, headers, body}) do
    body =
      case JSON.decode(body) do
        {:ok, map} -> map
        {:error, _} -> body
      end

    {:ok, status, headers, body}
  end
end
