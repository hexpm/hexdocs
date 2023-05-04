defmodule Hexdocs.TarTest do
  use ExUnit.Case, async: true
  alias Hexdocs.Tar

  test "unzip tar" do
    blob = Tar.create([{"index.html", "contents"}, {"foo.bar", "contents"}])

    assert {:ok, files} = Tar.unpack(blob)
    assert length(files) == 2
    assert {"index.html", "contents"} in files
    assert {"foo.bar", "contents"} in files
  end

  test "invalid gzip" do
    assert Tar.unpack("") == {:error, "invalid gzip"}
  end

  test "do not allow root files/directories with version names" do
    reason = "root file or directory name not allowed to match a semver version"

    blob = Tar.create([{"1.0.0", "contents"}])
    assert Tar.unpack(blob) == {:error, reason}

    blob = Tar.create([{"1.0.0/index.html", "contents"}])
    assert Tar.unpack(blob) == {:error, reason}
  end
end
