defmodule Hexdocs.Store do
  @type bucket :: atom
  @type prefix :: key
  @type key :: String.t()
  @type body :: binary
  @type opts :: Keyword.t()
  @type status :: 100..599
  @type headers :: %{String.t() => String.t()}

  @callback list(bucket, prefix) :: [key]
  @callback get(bucket, key, opts) :: body | nil
  @callback get_page(bucket, key, opts) :: {status, headers, body}
  @callback put(bucket, key, body, opts) :: term
  @callback delete(bucket, key) :: term
  @callback delete_many(bucket, [key]) :: [term]

  defp impl(), do: Application.get_env(:hexdocs, :store_impl)

  def list(bucket, prefix), do: impl().list(bucket, prefix)
  def get(bucket, key, opts \\ []), do: impl().get(bucket, key, opts)
  def get_page(bucket, key, opts \\ []), do: impl().get_page(bucket, key, opts)
  def put(bucket, key, body, opts \\ []), do: impl().put(bucket, key, body, opts)
  def delete(bucket, key), do: impl().delete(bucket, key)
  def delete_many(bucket, keys), do: impl().delete_many(bucket, keys)
end
