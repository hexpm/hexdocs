defmodule Hexdocs.TarTest do
  use ExUnit.Case, async: true
  alias Hexdocs.Tar

  test "unpack_to_dir" do
    blob = Tar.create([{"index.html", "contents"}, {"foo.bar", "contents"}])
    path = Hexdocs.TmpDir.tmp_file("test-tarball")
    File.write!(path, blob)

    assert {:ok, dir, files} = Tar.unpack_to_dir({:file, path})
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
    assert {:error, _} = Tar.unpack_to_dir({:file, path})
  end

  test "do not allow root files/directories with version names" do
    reason = "root file or directory name not allowed to match a semver version"

    blob = Tar.create([{"1.0.0", "contents"}])
    path = Hexdocs.TmpDir.tmp_file("test-tarball")
    File.write!(path, blob)
    assert Tar.unpack_to_dir({:file, path}) == {:error, reason}

    blob = Tar.create([{"1.0.0/index.html", "contents"}])
    File.write!(path, blob)
    assert Tar.unpack_to_dir({:file, path}) == {:error, reason}
  end
end
