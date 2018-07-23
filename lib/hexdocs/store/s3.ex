defmodule Hexdocs.Store.S3 do
  @behaviour Hexdocs.Store

  alias ExAws.S3

  def list(bucket, prefix) do
    S3.list_objects(bucket, prefix: prefix)
    |> ExAws.stream!()
    |> Stream.map(&Map.get(&1, :key))
  end

  def get(bucket, key, opts) do
    S3.get_object(bucket, key, opts)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def get_page(bucket, key, opts) do
    S3.get_object(bucket, key, opts)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} -> {200, [], body}
      {:error, {:http_error, status, _}} -> {status, [], ""}
    end
  end

  def put(bucket, key, blob, opts) do
    S3.put_object(bucket, key, blob, opts)
    |> ExAws.request!()
  end

  def delete(bucket, key) do
    S3.delete_object(bucket, key)
    |> ExAws.request!()
  end

  def delete_many(bucket, keys) do
    # AWS doesn't like concurrent delete requests
    keys
    |> Stream.chunk_every(1000, 1000, [])
    |> Enum.each(fn chunk ->
      S3.delete_multiple_objects(bucket, chunk)
      |> ExAws.request!()
    end)
  end
end
