defmodule HexDocsTest do
  use ExUnit.Case
  doctest HexDocs

  test "greets the world" do
    assert HexDocs.hello() == :world
  end
end
