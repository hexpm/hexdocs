defmodule Hexdocs.TarTest do
  use ExUnit.Case, async: true
  import Hexdocs.TestHelper
  alias Hexdocs.Tar

  test "unzip tar" do
    blob = create_tar([{"index.html", "contents"}, {"foo.bar", "contents"}])

    assert {:ok, files} = Tar.unpack(blob)
    assert length(files) == 2
    assert {"index.html", "contents"} in files
    assert {"foo.bar", "contents"} in files
  end

  test "do not allow root files/directories with version names" do
    reason = "root file or directory name not allowed to match a semver version"

    blob = create_tar([{"1.0.0", "contents"}])
    assert Tar.unpack(blob) == {:error, reason}

    blob = create_tar([{"1.0.0/index.html", "contents"}])
    assert Tar.unpack(blob) == {:error, reason}
  end
end
