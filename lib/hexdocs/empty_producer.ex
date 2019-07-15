# TODO: replace with the one from Broadway: https://github.com/plataformatec/broadway/pull/91
defmodule Hexdocs.EmptyProducer do
  @moduledoc false

  use GenStage
  @behaviour Broadway.Producer

  @impl true
  def init(_args) do
    {:producer, []}
  end

  @impl true
  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end
end
