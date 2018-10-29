defmodule Hexdocs.CDN.Local do
  @behaviour Hexdocs.CDN

  def purge_key(_service, _key), do: :ok
end
