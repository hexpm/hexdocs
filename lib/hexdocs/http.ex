defmodule Hexdocs.HTTP do
  @max_retry_times 5
  @base_sleep_time 200
  @receive_timeout 30_000

  require Logger

  def get(url, headers, opts \\ []) do
    timeout = Keyword.get(opts, :receive_timeout, @receive_timeout)

    case Req.get(url,
           headers: headers,
           retry: false,
           decode_body: false,
           receive_timeout: timeout
         ) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

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
           receive_timeout: @receive_timeout
         ) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put_file(url, headers, path) do
    body = File.stream!(path, 65_536)

    case Req.put(url,
           headers: headers,
           body: body,
           retry: false,
           decode_body: false,
           receive_timeout: @receive_timeout
         ) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def post(url, headers, body, opts \\ []) do
    timeout = Keyword.get(opts, :receive_timeout, @receive_timeout)

    case Req.post(url,
           headers: headers,
           body: body,
           retry: false,
           decode_body: false,
           receive_timeout: timeout
         ) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(url, headers, opts \\ []) do
    timeout = Keyword.get(opts, :receive_timeout, @receive_timeout)

    case Req.delete(url,
           headers: headers,
           retry: false,
           decode_body: false,
           receive_timeout: timeout
         ) do
      {:ok, response} ->
        {:ok, response.status, normalize_headers(response.headers), response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {name, values} -> {name, Enum.join(values, ", ")} end)
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
