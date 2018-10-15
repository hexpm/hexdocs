defmodule Hexdocs.Store.Impl do
  @behaviour Hexdocs.Store.Repo
  @behaviour Hexdocs.Store.Docs

  def list(bucket, prefix) do
    {impl, name} = bucket(bucket)
    impl.list(name, prefix)
  end

  def get(bucket, key, opts) do
    {impl, name} = bucket(bucket)
    impl.get(name, key, opts)
  end

  def head_page(bucket, key, opts) do
    {impl, name} = bucket(bucket)
    impl.head_page(name, key, opts)
  end

  def get_page(bucket, key, opts) do
    {impl, name} = bucket(bucket)
    impl.get_page(name, key, opts)
  end

  def stream_page(bucket, key, opts) do
    {impl, name} = bucket(bucket)
    impl.stream_page(name, key, opts)
  end

  def put(bucket, key, body, opts) do
    {impl, name} = bucket(bucket)
    impl.put(name, key, body, opts)
  end

  def delete(bucket, key) do
    {impl, name} = bucket(bucket)
    impl.delete(name, key)
  end

  def delete_many(bucket, keys) do
    {impl, name} = bucket(bucket)
    impl.delete_many(name, keys)
  end

  defp bucket(key) do
    env = Application.get_env(:hexdocs, key)
    {env[:implementation], env[:name]}
  end
end
