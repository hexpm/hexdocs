defmodule Hexdocs.Queue do
  def name() do
    Application.get_env(:hexdocs, :queue_name)
  end

  defmodule Producer do
    use GenStage

    @receive_opts [max_number_of_message: 10, wait_time_seconds: 10]

    def start_link(id) do
      GenStage.start_link(__MODULE__, [], name: id)
    end

    def init([]) do
      {:producer, %{demand: 0, queue: :queue.new()}}
    end

    def handle_demand(new_demand, state) do
      dispatch(%{state | demand: state.demand + new_demand}, [])
    end

    def handle_info(:pull, state) do
      pull(state)
    end

    defp dispatch(%{demand: 0} = state, events) do
      {:noreply, events, state}
    end

    defp dispatch(%{queue: queue, demand: demand} = state, events) do
      case :queue.out(queue) do
        {{:value, message}, queue} ->
          dispatch(%{state | queue: queue, demand: demand - 1}, [message | events])

        {:empty, queue} ->
          send(self(), :pull)
          {:noreply, events, %{state | queue: queue}}
      end
    end

    defp pull(%{demand: 0} = state) do
      send(self(), :pull)
      {:noreply, [], state}
    end

    defp pull(state) do
      %{status_code: 200, body: body} =
        ExAws.SQS.receive_message(Hexdocs.Queue.name(), @receive_opts)
        |> ExAws.request!()

      queue = Enum.reduce(body.messages, state.queue, &:queue.in/2)
      dispatch(%{state | queue: queue}, [])
    end
  end

  defmodule Consumer do
    use GenStage
    require Logger

    def start_link(id, opts) do
      GenStage.start_link(__MODULE__, opts, name: id)
    end

    def init(opts) do
      {:consumer, [], opts}
    end

    def handle_events(messages, _from, state) do
      Enum.each(messages, fn message ->
        body = Jason.decode!(message.body)
        handle_message(body)

        ExAws.SQS.delete_message(Hexdocs.Queue.name(), message.receipt_handle)
        |> ExAws.request!()
      end)

      {:noreply, [], state}
    end

    def handle_message(%{"Event" => "s3:TestEvent"}) do
      :ok
    end

    def handle_message(%{"Records" => records}) do
      Enum.each(records, &handle_record/1)
    end

    defp handle_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}) do
      key = s3["object"]["key"]
      Logger.info "Processing docs #{key}"

      case key_components(key) do
        {:ok, repository, package, version} ->
          body = Hexdocs.Store.get(:repo_bucket, key)

          # TODO: Handle errors
          {:ok, files} = Hexdocs.Tar.parse(body)
          version = Version.parse!(version)
          all_versions = all_versions(repository, package, version)
          Hexdocs.Bucket.upload(repository, package, version, all_versions, files)
          Logger.info "Finished processing docs #{key}"

        :error ->
          :ok
      end
    end

    defp key_components(key) do
      case Path.split(key) do
        ["repos", repository, "docs", file] ->
          base = Path.basename(file, ".tar.gz")
          [package, version] = String.split(base, "-", parts: 2)
          {:ok, repository, package, version}

        _ ->
          :error
      end
    end

    defp all_versions(repository, package, version) do
      package = Hexdocs.Hexpm.get_package(repository, package)

      package["releases"]
      |> Enum.filter(&(&1["has_docs"] and &1["version"] != version))
      |> Enum.map(&Version.parse!(&1["version"]))
      |> Enum.sort(&(Version.compare(&1, &2) == :gt))
    end
  end
end
