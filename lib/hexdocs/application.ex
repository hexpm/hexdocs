defmodule Hexdocs.Application do
  use Application

  def start(_type, _args) do
    setup_tmp_dir()
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{})

    children = [
      Hexdocs.TmpDir,
      {Task.Supervisor, name: Hexdocs.Tasks},
      {Hexdocs.Debouncer, name: Hexdocs.Debouncer},
      goth_spec(),
      Hexdocs.Queue
    ]

    opts = [strategy: :one_for_one, name: Hexdocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def sentry_before_send(%Sentry.Event{original_exception: exception} = event) do
    if Sentry.DefaultEventFilter.exclude_exception?(exception, event.source) do
      nil
    else
      event
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
