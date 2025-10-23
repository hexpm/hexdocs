defmodule Hexdocs.Application do
  use Application

  require Logger

  def start(_type, _args) do
    setup_tmp_dir()
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{})

    port = String.to_integer(Application.get_env(:hexdocs, :port))
    cowboy_options = [port: port]
    Logger.info("Running Cowboy with #{inspect(cowboy_options)}")

    children = [
      {Task.Supervisor, name: Hexdocs.Tasks},
      {Hexdocs.Debouncer, name: Hexdocs.Debouncer},
      goth_spec(),
      Plug.Cowboy.child_spec(scheme: :http, plug: Hexdocs.Plug, options: cowboy_options),
      Hexdocs.Queue
    ]

    opts = [strategy: :one_for_one, name: Hexdocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def sentry_before_send(%Sentry.Event{original_exception: exception} = event) do
    cond do
      Plug.Exception.status(exception) < 500 -> nil
      Sentry.DefaultEventFilter.exclude_exception?(exception, event.source) -> nil
      true -> event
    end
  end

  if Mix.env() == :prod do
    defp goth_spec() do
      credentials =
        "HEXDOCS_GCP_CREDENTIALS"
        |> System.fetch_env!()
        |> JSON.decode!()

      options = [scopes: ["https://www.googleapis.com/auth/devstorage.read_write"]]
      {Goth, name: Hexdocs.Goth, source: {:service_account, credentials, options}}
    end
  else
    defp goth_spec() do
      Supervisor.child_spec({Task, fn -> :ok end}, id: :goth)
    end
  end

  defp setup_tmp_dir() do
    if dir = Application.get_env(:hexdocs, :tmp_dir) do
      File.mkdir_p!(dir)
      Application.put_env(:hexdocs, :tmp_dir, Path.expand(dir))
    end
  end
end
