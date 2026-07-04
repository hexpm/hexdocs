defmodule Hexdocs.CDN.Local do
  @behaviour Hexdocs.CDN

  def purge_key(service, key) do
    send(self(), {:purge, service, key})
    :ok
  end
end
