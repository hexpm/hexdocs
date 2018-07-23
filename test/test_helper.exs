File.rm_rf("tmp")
File.mkdir("tmp")

Mox.defmock(Hexdocs.HexpmMock, for: Hexdocs.Hexpm)
ExUnit.start()

defmodule Hexdocs.TestHelper do
  def create_tar(files) do
    File.mkdir_p!("tmp/tartest")

    filename = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    path = Path.join("tmp/tartest", filename <> ".tar.gz")

    try do
      files =
        Enum.map(files, fn {filename, contents} ->
          {String.to_charlist(filename), contents}
        end)

      :ok = :erl_tar.create(path, files, [:compressed])
      File.read!(path)
    after
      File.rm(path)
    end
  end
end
