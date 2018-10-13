defmodule Hexdocs.Application do
  use Application

  alias Hexdocs.Queue, warn: false

  def start(_type, _args) do
    setup_tmp_dir()

    children = [cowboy_spec()] ++ queue_producer_specs() ++ queue_consumer_specs()
    opts = [strategy: :one_for_one, name: Hexdocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cowboy_spec() do
    port = String.to_integer(Application.get_env(:hexdocs, :port))
    Plug.Adapters.Cowboy.child_spec(scheme: :http, plug: Hexdocs.Plug, options: [port: port])
  end

  if Mix.env() == :prod do
    @num_queue_consumers 4

    defp queue_producer_specs() do
      [%{id: Queue.Producer, start: {Queue.Producer, :start_link, [Queue.Producer]}}]
    end

    defp queue_consumer_specs() do
      Enum.map(1..@num_queue_consumers, fn ix ->
        opts = [subscribe_to: [{Queue.Producer, max_demand: 2, min_demand: 1}]]
        id = Module.concat(Queue.Consumer, Integer.to_string(ix))
        %{id: id, start: {Queue.Consumer, :start_link, [id, opts]}}
      end)
    end
  else
    defp queue_producer_specs(), do: []
    defp queue_consumer_specs(), do: []
  end

  defp setup_tmp_dir() do
    if dir = Application.get_env(:hexdocs, :tmp_dir) do
      File.mkdir_p!(dir)
      Application.put_env(:hexdocs, :tmp_dir, Path.expand(dir))
    end
  end
end
