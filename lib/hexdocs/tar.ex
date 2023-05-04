defmodule Hexdocs.Tar do
  require Logger

  @zlib_magic 16 + 15
  @compressed_max_size 16 * 1024 * 1024
  @uncompressed_max_size 128 * 1024 * 1024

  def create(files) do
    files = for {path, contents} <- files, do: {String.to_charlist(path), contents}
    {:ok, tarball} = :hex_tarball.create_docs(files)
    tarball
  end

  def unpack(body, opts \\ []) do
    repository = Keyword.get(opts, :repository, "UNKNOWN")
    package = Keyword.get(opts, :package, "UNKNOWN")
    version = Keyword.get(opts, :version, "UNKNOWN")

    with {:ok, data} <- unzip(body),
         {:ok, files} <- :erl_tar.extract({:binary, data}, [:memory]),
         files = fix_paths(repository, package, version, files),
         :ok <- check_version_dirs(files),
         do: {:ok, files}
  end

  defp unzip(data) when byte_size(data) > @compressed_max_size do
    {:error, "too big"}
  end

  defp unzip(data) do
    stream = :zlib.open()

    try do
      :zlib.inflateInit(stream, @zlib_magic)
      uncompressed = unzip_inflate(stream, "", 0, :zlib.safeInflate(stream, data))
      :zlib.inflateEnd(stream)
      uncompressed
    after
      :zlib.close(stream)
    end
  end

  defp unzip_inflate(_stream, _data, total, _) when total > @uncompressed_max_size do
    {:error, "too big"}
  end

  defp unzip_inflate(stream, data, total, {:continue, uncompressed}) do
    total = total + IO.iodata_length(uncompressed)
    unzip_inflate(stream, [data | uncompressed], total, :zlib.safeInflate(stream, []))
  end

  defp unzip_inflate(_stream, data, total, {:finished, uncompressed}) do
    if total + IO.iodata_length(uncompressed) > @uncompressed_max_size do
      {:error, "too big"}
    else
      {:ok, IO.iodata_to_binary([data | uncompressed])}
    end
  end

  defp check_version_dirs(files) do
    result =
      Enum.all?(files, fn {path, _data} ->
        first = Path.split(path) |> hd()
        Version.parse(first) == :error
      end)

    if result do
      :ok
    else
      {:error, "root file or directory name not allowed to match a semver version"}
    end
  end

  defp fix_paths(repository, package, version, files) do
    Enum.flat_map(files, fn {path, data} ->
      case safe_path(path) do
        {:ok, path} ->
          [{path, data}]

        :error ->
          Logger.error("Unsafe path from #{repository}/#{package} #{version}: #{path}")
          []
      end
    end)
  end

  defp safe_path(path) do
    case safe_path(Path.split(path), []) do
      {:ok, path} -> {:ok, Path.join(path)}
      :error -> :error
    end
  end

  defp safe_path(["." | rest], acc), do: safe_path(rest, acc)
  defp safe_path([".." | rest], [_prev | acc]), do: safe_path(rest, acc)
  defp safe_path([".." | _rest], []), do: :error
  defp safe_path([path | rest], acc), do: safe_path(rest, [path | acc])
  defp safe_path([], []), do: :error
  defp safe_path([], acc), do: {:ok, Enum.reverse(acc)}
end
