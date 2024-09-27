File.rm_rf("tmp")
File.mkdir("tmp")

Mox.defmock(Hexdocs.HexpmMock, for: Hexdocs.Hexpm)
Mox.defmock(Hexdocs.SourceRepo.Mock, for: Hexdocs.SourceRepo)

exclude =
  case Hexdocs.HTTP.get("http://localhost:8108/health", _req_headers = []) do
    {:ok, 200, _resp_headers, ~s|{"ok":true}|} ->
      _no_exclude = []

    {:error, :econnrefused} ->
      Mix.shell().error("""
      To enable Typesense tests, start the local container with the following command:

          docker run -d --rm -p 8108:8108 typesense/typesense:26.0 --data-dir /tmp --api-key=hexdocs
      """)

      _exclude_typesense = [:typesense]
  end

ExUnit.start(exclude: exclude)
