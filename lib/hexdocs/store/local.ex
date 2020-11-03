defmodule Hexdocs.Store.Local do
  @behaviour Hexdocs.Store.Repo
  @behaviour Hexdocs.Store.Docs

  def list(bucket, prefix) do
    relative = Path.join([dir(), bucket(bucket)])
    paths = Path.join(relative, "**") |> Path.wildcard()

    Enum.flat_map(paths, fn path ->
      relative = Path.relative_to(path, relative)

      if String.starts_with?(relative, prefix) and File.regular?(path) do
        [relative]
      else
        []
      end
    end)
  end

  def get(bucket, key, _opts) do
    path = Path.join([dir(), bucket(bucket), key])

    case File.read(path) do
      {:ok, contents} -> contents
      {:error, :enoent} -> nil
    end
  end

  def head_page(bucket, key, _opts) do
    path = Path.join([dir(), bucket(bucket), key])

    if File.regular?(path) do
      {200, []}
    else
      {404, []}
    end
  end

  def get_page(bucket, key, _opts) do
    path = Path.join([dir(), bucket(bucket), key])

    case File.read(path) do
      {:ok, contents} -> {200, [], contents}
      {:error, :eisdir} -> {404, [], ""}
      {:error, :enoent} -> {404, [], ""}
    end
  end

  def stream_page(bucket, key, _opts) do
    path = Path.join([dir(), bucket(bucket), key])

    case File.read(path) do
      {:ok, contents} -> {200, [], Stream.map(:binary.bin_to_list(contents), &{:ok, <<&1>>})}
      {:error, :eisdir} -> {404, [], []}
      {:error, :enoent} -> {404, [], []}
    end
  end

  def put(bucket, key, blob, _opts) do
    path = Path.join([dir(), bucket(bucket), key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
    {:ok, 200, [], ""}
  end

  def put!(bucket, key, blob, _opts) do
    path = Path.join([dir(), bucket(bucket), key])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, blob)
  end

  def delete(bucket, key) do
    [dir(), bucket(bucket), key]
    |> Path.join()
    |> File.rm_rf!()
  end

  def delete_many(bucket, keys) do
    Enum.each(keys, &delete(bucket, &1))
  end

  defp bucket(atom) when is_atom(atom) do
    Application.get_env(:hexdocs, atom)[:name]
  end

  defp dir() do
    Application.get_env(:hexdocs, :tmp_dir)
    |> Path.join("store")
  end
end
