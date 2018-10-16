defmodule Hexdocs.Store do
  @type bucket :: atom
  @type prefix :: key
  @type key :: String.t()
  @type body :: binary
  @type opts :: Keyword.t()
  @type status :: 100..599
  @type headers :: %{String.t() => String.t()}

  defmodule Repo do
    @type bucket :: atom
    @type key :: String.t()
    @type body :: binary
    @type opts :: Keyword.t()

    @callback get(bucket, key, opts) :: body | nil
  end

  defmodule Docs do
    @type bucket :: atom
    @type prefix :: key
    @type key :: String.t()
    @type body :: binary
    @type stream :: Enum.t()
    @type opts :: Keyword.t()
    @type status :: 100..599
    @type headers :: %{String.t() => String.t()}

    @callback list(bucket, prefix) :: [key]
    @callback head_page(bucket, key, opts) :: {status, headers}
    @callback get_page(bucket, key, opts) :: {status, headers, body}
    @callback stream_page(bucket, key, opts) :: {status, headers, stream}
    @callback put(bucket, key, body, opts) :: term
    @callback delete_many(bucket, [key]) :: [term]
  end

  defp impl(), do: Application.get_env(:hexdocs, :store_impl)

  def list(bucket, prefix), do: impl().list(bucket, prefix)
  def get(bucket, key, opts \\ []), do: impl().get(bucket, key, opts)
  def head_page(bucket, key, opts \\ []), do: impl().head_page(bucket, key, opts)
  def get_page(bucket, key, opts \\ []), do: impl().get_page(bucket, key, opts)
  def stream_page(bucket, key, opts \\ []), do: impl().stream_page(bucket, key, opts)
  def put(bucket, key, body, opts \\ []), do: impl().put(bucket, key, body, opts)
  def delete_many(bucket, keys), do: impl().delete_many(bucket, keys)
end
