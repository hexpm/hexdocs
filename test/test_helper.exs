File.rm_rf("tmp")
File.mkdir("tmp")

Mox.defmock(Hexdocs.HexpmMock, for: Hexdocs.Hexpm)
Mox.defmock(Hexdocs.SourceRepo.Mock, for: Hexdocs.SourceRepo)
Mox.defmock(Hexdocs.HexRepo.Mock, for: Hexdocs.HexRepo)

if :typesense in ExUnit.configuration()[:include] do
  typesense_available? =
    case Hexdocs.HTTP.get("http://localhost:8108/health", _req_headers = []) do
      {:ok, 200, _resp_headers, ~s|{"ok":true}|} -> true
      {:error, :econnrefused} -> false
    end

  unless typesense_available? do
    Mix.shell().error("""
    To enable Typesense tests, start the local container with the following command:

        docker compose up -d typesense
    """)
  end
end

ExUnit.start(exclude: [:typesense])
