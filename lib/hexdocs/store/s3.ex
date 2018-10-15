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
end
