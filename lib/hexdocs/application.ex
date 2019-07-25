defmodule Hexdocs.Application do
  use Application

  require Logger
  alias Hexdocs.Queue, warn: false

  def start(_type, _args) do
    setup_tmp_dir()

    port = String.to_integer(Application.get_env(:hexdocs, :port))
    cowboy_options = [port: port]
    Logger.info("Running Cowboy with #{inspect(cowboy_options)}")

    children = [
      Plug.Cowboy.child_spec(scheme: :http, plug: Hexdocs.Plug, options: cowboy_options),
      Hexdocs.Queue
    ]

    opts = [strategy: :one_for_one, name: Hexdocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp setup_tmp_dir() do
    if dir = Application.get_env(:hexdocs, :tmp_dir) do
      File.mkdir_p!(dir)
      Application.put_env(:hexdocs, :tmp_dir, Path.expand(dir))
    end
  end
end
