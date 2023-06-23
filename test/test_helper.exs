File.rm_rf("tmp")
File.mkdir("tmp")

Mox.defmock(Hexdocs.HexpmMock, for: Hexdocs.Hexpm)
Mox.defmock(Hexdocs.SourceRepo.Mock, for: Hexdocs.SourceRepo)
ExUnit.start()
