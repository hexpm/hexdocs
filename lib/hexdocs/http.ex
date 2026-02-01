defmodule Hexdocs.HTTP do
  @max_retry_times 5
  @base_sleep_time 200

  require Logger

  def head(url, headers) do
    case Req.head(url, headers: headers, retry: false, decode_body: false) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get(url, headers, _opts \\ []) do
    case Req.get(url, headers: headers, retry: false, decode_body: false) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_stream(url, headers) do
    case Req.get(url, headers: headers, retry: false, decode_body: false, into: :self) do
      {:ok, response} ->
        stream = stream_body(response.body.ref)
        {:ok, response.status, normalize_headers(response.headers), stream}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put(url, headers, body) do
    case Req.put(url,
           headers: headers,
           body: body,
           retry: false,
           decode_body: false,
           receive_timeout: 10_000
         ) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def post(url, headers, body, _opts \\ []) do
    case Req.post(url, headers: headers, body: body, retry: false, decode_body: false) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(url, headers, _opts \\ []) do
    case Req.delete(url, headers: headers, retry: false, decode_body: false) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {name, values} -> {name, Enum.join(values, ", ")} end)
  end

  defp stream_body(ref) do
    start_fun = fn -> :cont end
    after_fun = fn _ -> :ok end

    next_fun = fn
      :cont ->
        receive do
          {^ref, {:data, data}} -> {[{:ok, data}], :cont}
          {^ref, :done} -> {:halt, :ok}
        after
          30_000 -> {[{:error, :timeout}], :stop}
        end

      :stop ->
        {:halt, :ok}
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  def retry(service, url, fun) do
    retry(fun, service, url, 0)
  end

  defp retry(fun, service, url, times) do
    case fun.() do
      {:ok, status, _headers, _body} when status in 500..599 or status == 429 ->
        do_retry(fun, service, url, times, "status #{status}")

      {:error, reason} ->
        do_retry(fun, service, url, times, reason)

      result ->
        result
    end
  end

  defp do_retry(fun, service, url, times, reason) do
    Logger.warning("#{service} API ERROR #{url}: #{inspect(reason)}")

    if times + 1 < @max_retry_times do
      sleep = trunc(:math.pow(3, times) * @base_sleep_time)
      :timer.sleep(sleep)
      retry(fun, service, url, times + 1)
    else
      {:error, reason}
    end
  end
end
