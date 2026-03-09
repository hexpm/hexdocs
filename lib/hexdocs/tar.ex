defmodule Hexdocs.Tar do
  require Logger

  def create(files) do
    files = for {path, contents} <- files, do: {String.to_charlist(path), contents}
    {:ok, tarball} = :hex_tarball.create_docs(files)
    tarball
  end

  def unpack_to_dir({:file, path}, opts \\ []) do
    repository = Keyword.get(opts, :repository, "UNKNOWN")
    package = Keyword.get(opts, :package, "UNKNOWN")
    version = Keyword.get(opts, :version, "UNKNOWN")

    output_dir = Hexdocs.TmpDir.tmp_dir("docs")

    case :hex_tarball.unpack_docs({:file, to_charlist(path)}, to_charlist(output_dir)) do
      :ok ->
        files =
          output_dir
          |> Path.join("**")
          |> Path.wildcard(match_dot: true)
          |> Enum.filter(&File.regular?(&1, raw: true))
          |> Enum.map(&Path.relative_to(&1, output_dir))

        files = fix_paths(repository, package, version, files)

        case check_version_dirs(files) do
          :ok -> {:ok, output_dir, files}
          {:error, _} = error -> error
        end

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp check_version_dirs(files) do
    result =
      Enum.all?(files, fn path ->
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
    Enum.flat_map(files, fn path ->
      case safe_path(path) do
        {:ok, path} ->
          [path]

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
