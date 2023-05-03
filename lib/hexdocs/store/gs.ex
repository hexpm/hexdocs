defmodule Hexdocs.Store.GS do
  @behaviour Hexdocs.Store.Docs

  @gs_xml_url "https://storage.googleapis.com"

  import SweetXml, only: [sigil_x: 2]

  def list(bucket, prefix) do
    list_stream(bucket, prefix)
  end

  def head_page(bucket, key, _opts) do
    url = url(bucket, key)

    {:ok, status, headers} = Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.head(url, headers()) end)

    {status, headers}
  end

  def get_page(bucket, key, _opts) do
    url = url(bucket, key)

    {:ok, status, headers, body} =
      Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.get(url, headers()) end)

    {status, headers, body}
  end

  def stream_page(bucket, key, _opts) do
    url = url(bucket, key)

    {:ok, status, headers, stream} =
      Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.get_stream(url, headers()) end)

    {status, headers, stream}
  end

  def put(bucket, key, blob, opts) do
    headers =
      headers() ++
        meta_headers(Keyword.fetch!(opts, :meta)) ++
        [
          {"cache-control", Keyword.fetch!(opts, :cache_control)},
          {"content-type", Keyword.get(opts, :content_type)}
        ]

    url = url(bucket, key)
    headers = filter_nil_values(headers)

    Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.put(url, headers, blob) end)
  end

  def put!(bucket, key, blob, opts) do
    headers =
      headers() ++
        meta_headers(Keyword.fetch!(opts, :meta)) ++
        [
          {"cache-control", Keyword.fetch!(opts, :cache_control)},
          {"content-type", Keyword.get(opts, :content_type)}
        ]

    url = url(bucket, key)
    headers = filter_nil_values(headers)

    {:ok, 200, _headers, _body} =
      Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.put(url, headers, blob) end)

    :ok
  end

  def delete_many(bucket, keys) do
    keys
    |> Task.async_stream(
      &delete(bucket, &1),
      max_concurrency: 10,
      timeout: 10_000
    )
    |> Hexdocs.Utils.raise_async_stream_error()
    |> Stream.run()
  end

  defp delete(bucket, key) do
    url = url(bucket, key)

    {:ok, 204, _headers, _body} =
      Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.delete(url, headers()) end)

    :ok
  end

  defp list_stream(bucket, prefix) do
    start_fun = fn -> nil end
    after_fun = fn _ -> nil end

    next_fun = fn
      :halt ->
        {:halt, nil}

      marker ->
        {items, marker} = do_list(bucket, prefix, marker)
        {items, marker || :halt}
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  defp do_list(bucket, prefix, marker) do
    url = url(bucket) <> "?prefix=#{prefix}&marker=#{marker}"

    {:ok, 200, _headers, body} =
      Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.get(url, headers()) end)

    doc = SweetXml.parse(body)
    marker = SweetXml.xpath(doc, ~x"/ListBucketResult/NextMarker/text()"s)
    items = SweetXml.xpath(doc, ~x"/ListBucketResult/Contents/Key/text()"ls)
    marker = if marker != "", do: marker

    {Enum.map(items, &URI.decode/1), marker}
  end

  defp filter_nil_values(keyword) do
    Enum.reject(keyword, fn {_key, value} -> is_nil(value) end)
  end

  defp headers() do
    {:ok, token} = Goth.fetch(Hexdocs.Goth)
    [{"authorization", "#{token.type} #{token.token}"}]
  end

  defp meta_headers(meta) do
    Enum.map(meta, fn {key, value} ->
      {"x-goog-meta-#{key}", value}
    end)
  end

  defp url(bucket) do
    @gs_xml_url <> "/" <> bucket
  end

  defp url(bucket, key) do
    url(bucket) <> "/" <> URI.encode(key)
  end
end
