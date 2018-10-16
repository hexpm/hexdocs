defmodule Hexdocs.Store.GS do
  @behaviour Hexdocs.Store.Docs

  @gs_xml_url "https://storage.googleapis.com"
  @oauth_scope "https://www.googleapis.com/auth/devstorage.read_write"

  import SweetXml, only: [sigil_x: 2]

  def list(bucket, prefix) do
    list_stream(bucket, prefix)
  end

  def head_page(bucket, key, _opts) do
    url = url(bucket, key)

    {:ok, status, headers} = Hexdocs.HTTP.retry("gs", fn -> Hexdocs.HTTP.head(url, headers()) end)

    {status, headers}
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
          {"content-type", Keyword.fetch!(opts, :content_type)}
        ]

    url = url(bucket, key)

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
    marker = SweetXml.xpath(doc, ~x"/ListBucketResult/Marker/text()"s)
    items = SweetXml.xpath(doc, ~x"/ListBucketResult/Contents/Key/text()"ls)
    marker = if marker != "", do: marker

    {items, marker}
  end

  defp headers() do
    {:ok, token} = Goth.Token.for_scope(@oauth_scope)
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
    url(bucket) <> "/" <> key
  end
end
