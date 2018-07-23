defmodule Hexdocs.HTTP do
  @max_retry_times 3
  @base_sleep_time 100

  require Logger

  def get(url, headers) do
    :hackney.get(url, headers)
    |> read_request()
  end

  def put(url, headers, body) do
    :hackney.put(url, headers, body)
    |> read_request()
  end

  def delete(url, headers) do
    :hackney.delete(url, headers)
    |> read_request()
  end

  defp read_request(result) do
    with {:ok, status, headers, ref} <- result,
         {:ok, body} <- :hackney.body(ref) do
      {:ok, status, headers, body}
    end
  end

  def retry(service, fun) do
    retry(fun, service, 0)
  end

  defp retry(fun, service, times) do
    case fun.() do
      {:error, reason} ->
        Logger.warn("#{service} API ERROR: #{inspect(reason)}")

        if times + 1 < @max_retry_times do
          sleep = trunc(:math.pow(3, times) * @base_sleep_time)
          :timer.sleep(sleep)
          retry(fun, service, times + 1)
        else
          {:error, reason}
        end

      result ->
        result
    end
  end
end
