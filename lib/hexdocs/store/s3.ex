defmodule Hexdocs.Store.S3 do
  @behaviour Hexdocs.Store.Repo

  def get(bucket, key, opts) do
    ExAws.S3.get_object(bucket, key, opts)
    |> ExAws.request()
    |> case do
      {:ok, result} -> result.body
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def get_to_file(bucket, key, dest, _opts) do
    case ExAws.S3.download_file(bucket, key, dest) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, {:http_error, 404, _}} -> nil
    end
  end

  def list(bucket, prefix) do
    ExAws.S3.list_objects(bucket, prefix: prefix)
    |> ExAws.stream!()
    |> Stream.map(&Map.get(&1, :key))
  end
end
