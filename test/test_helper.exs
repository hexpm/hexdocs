File.rm_rf("tmp")
File.mkdir("tmp")

Mox.defmock(Hexdocs.HexpmMock, for: Hexdocs.Hexpm)
ExUnit.start()
