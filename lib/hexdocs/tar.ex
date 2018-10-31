defmodule Hexdocs.Tar do
  @zlib_magic 16 + 15
  @compressed_max_size 8 * 1024 * 1024
  @uncompressed_max_size 64 * 1024 * 1024

  def unpack(body) do
    with {:ok, data} <- unzip(body),
         {:ok, files} <- :erl_tar.extract({:binary, data}, [:memory]),
         files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end),
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
end
