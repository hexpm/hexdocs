defmodule Hexdocs.Queue do
  def name() do
    Application.get_env(:hexdocs, :queue_name)
  end

  defmodule Producer do
    use GenStage

    @receive_opts [max_number_of_message: 10, wait_time_seconds: 10]
    @task_timeout 60_000

    def start_link(id) do
      GenStage.start_link(__MODULE__, [], name: id)
    end

    def init([]) do
      {:producer, %{demand: 0, queue: :queue.new(), pulling: false}}
    end

    def handle_demand(new_demand, state) do
      dispatch(%{state | demand: state.demand + new_demand}, [])
    end

    def handle_info(:pull, state) do
      state = %{state | pulling: false}
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
          state = send_pull(state)
          {:noreply, events, %{state | queue: queue}}
      end
    end

    defp pull(%{demand: 0} = state) do
      {:noreply, [], state}
    end

    defp pull(state) do
      opts = Keyword.update!(@receive_opts, :max_number_of_message, &min(&1, state.demand))
      %{status_code: 200, body: body} = request(Hexdocs.Queue.name(), opts)

      queue = Enum.reduce(body.messages, state.queue, &:queue.in/2)
      dispatch(%{state | queue: queue}, [])
    end

    defp send_pull(%{pulling: false} = state) do
      send(self(), :pull)
      %{state | pulling: true}
    end

    defp send_pull(%{pulling: true} = state) do
      state
    end

    # Do this to avoid leaking :ssl_closed messages from hackney
    defp request(name, opts) do
      Task.async(fn ->
        ExAws.SQS.receive_message(name, opts)
        |> ExAws.request!()
      end)
      |> Task.await(@task_timeout)
    end
  end

  defmodule Consumer do
    use GenStage
    require Logger

    @ignore_packages ~w(eex elixir ex_unit iex logger mix hex)

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
      Logger.info("OBJECT CREATED #{key}")

      case key_components(key) do
        {:ok, repository, package, version} ->
          body = Hexdocs.Store.get(:repo_bucket, key)

          # TODO: Handle errors
          {:ok, files} = Hexdocs.Tar.unpack(body)
          version = Version.parse!(version)
          all_versions = all_versions(repository, package)
          Hexdocs.Bucket.upload(repository, package, version, all_versions, files)
          update_sitemap(repository)
          Logger.info("FINISHED UPLOADING DOCS #{key}")

        :error ->
          :ok
      end
    end

    defp handle_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}) do
      key = s3["object"]["key"]
      Logger.info("OBJECT DELETED #{key}")

      case key_components(key) do
        {:ok, repository, package, version} ->
          version = Version.parse!(version)
          all_versions = all_versions(repository, package)
          Hexdocs.Bucket.delete(repository, package, version, all_versions)
          update_sitemap(repository)
          Logger.info("FINISHED DELETING DOCS #{key}")

        :error ->
          :ok
      end
    end

    defp key_components(key) do
      case Path.split(key) do
        ["repos", repository, "docs", file] ->
          {package, version} = filename_to_release(file)
          {:ok, repository, package, version}

        ["docs", file] ->
          case filename_to_release(file) do
            {package, _version} when package in @ignore_packages -> :error
            {package, version} -> {:ok, "hexpm", package, version}
          end

        _ ->
          :error
      end
    end

    defp filename_to_release(file) do
      base = Path.basename(file, ".tar.gz")
      [package, version] = String.split(base, "-", parts: 2)
      {package, version}
    end

    defp all_versions(repository, package) do
      if package = Hexdocs.Hexpm.get_package(repository, package) do
        package["releases"]
        |> Enum.filter(& &1["has_docs"])
        |> Enum.map(&Version.parse!(&1["version"]))
        |> Enum.sort(&(Version.compare(&1, &2) == :gt))
      else
        []
      end
    end

    defp update_sitemap("hexpm") do
      Logger.info("UPDATING SITEMAP")

      body = Hexdocs.Hexpm.hexdocs_sitemap()
      Hexdocs.Bucket.upload_sitemap(body)

      Logger.info("UPDATED SITEMAP")
    end

    defp update_sitemap(_repository) do
      :ok
    end
  end
end
