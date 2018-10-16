defmodule Hexdocs.HTTP do
  @max_retry_times 3
  @base_sleep_time 100

  require Logger

  def head(url, headers) do
    :hackney.head(url, headers)
  end

  def get(url, headers) do
    :hackney.get(url, headers)
    |> read_response()
  end

  def get_stream(url, headers) do
    :hackney.get(url, headers)
    |> stream_response()
  end

  def put(url, headers, body) do
    :hackney.put(url, headers, body)
    |> read_response()
  end

  def delete(url, headers) do
    :hackney.delete(url, headers)
    |> read_response()
  end

  defp read_response(result) do
    with {:ok, status, headers, ref} <- result,
         {:ok, body} <- :hackney.body(ref) do
      {:ok, status, headers, body}
    end
  end

  defp stream_response({:ok, status, headers, ref}) do
    start_fun = fn -> :cont end
    after_fun = fn _ -> :ok end

    next_fun = fn
      :cont ->
        case :hackney.stream_body(ref) do
          {:ok, data} -> {[{:ok, data}], :stop}
          :done -> {:halt, :ok}
          {:error, reason} -> {[{:error, reason}], :stop}
        end

      :stop ->
        {:halt, :ok}
    end

    {:ok, status, headers, Stream.resource(start_fun, next_fun, after_fun)}
  end

  defp stream_response(other) do
    other
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
