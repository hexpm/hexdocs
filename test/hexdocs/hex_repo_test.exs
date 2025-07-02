defmodule Hexdocs.HexRepo.HTTPTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  test "it works" do
    assert {:ok, names} = Hexdocs.HexRepo.HTTP.get_names()
    assert "hex_core" in names
  end
end
