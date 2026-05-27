defmodule Hexdocs.TarTest do
  use ExUnit.Case, async: true
  alias Hexdocs.Tar

  test "unpack_to_dir!" do
    blob = Tar.create([{"index.html", "contents"}, {"foo.bar", "contents"}])
    path = Hexdocs.TmpDir.tmp_file("test-tarball")
    File.write!(path, blob)

    assert {dir, files} = Tar.unpack_to_dir!({:file, path})
    assert File.dir?(dir)
    assert length(files) == 2
    assert "index.html" in files
    assert "foo.bar" in files
    assert File.read!(Path.join(dir, "index.html")) == "contents"
    assert File.read!(Path.join(dir, "foo.bar")) == "contents"
  end

  test "invalid gzip" do
    path = Hexdocs.TmpDir.tmp_file("test-tarball")
    File.write!(path, "")

    assert_raise Tar.UnpackError, ~r/Failed to unpack hexpm\/foo 1\.0\.0:/, fn ->
      Tar.unpack_to_dir!({:file, path}, repository: "hexpm", package: "foo", version: "1.0.0")
    end
  end

  test "do not allow root files/directories with version names" do
    blob = Tar.create([{"1.0.0", "contents"}])
    path = Hexdocs.TmpDir.tmp_file("test-tarball")
    File.write!(path, blob)

    assert_raise Tar.UnpackError,
                 ~r/root file or directory name not allowed to match a semver version/,
                 fn ->
                   Tar.unpack_to_dir!({:file, path},
                     repository: "hexpm",
                     package: "foo",
                     version: "1.0.0"
                   )
                 end

    blob = Tar.create([{"1.0.0/index.html", "contents"}])
    File.write!(path, blob)

    assert_raise Tar.UnpackError,
                 ~r/root file or directory name not allowed to match a semver version/,
                 fn ->
                   Tar.unpack_to_dir!({:file, path},
                     repository: "hexpm",
                     package: "foo",
                     version: "1.0.0"
                   )
                 end
  end

  test "raises on tarball with duplicate mode-0 entries" do
    path = Hexdocs.TmpDir.tmp_file("test-tarball")
    {:ok, tar} = :hex_erl_tar.open(String.to_charlist(path), [:write, :compressed])

    for _ <- 1..3 do
      :ok = :hex_erl_tar.add(tar, "contents", ~c"#", [{:mode, 0}])
    end

    :ok = :hex_erl_tar.close(tar)

    assert_raise Tar.UnpackError,
                 ~r/Failed to unpack hexpm\/lustre 5\.7\.0: :eacces/,
                 fn ->
                   Tar.unpack_to_dir!({:file, path},
                     repository: "hexpm",
                     package: "lustre",
                     version: "5.7.0"
                   )
                 end
  end
end
