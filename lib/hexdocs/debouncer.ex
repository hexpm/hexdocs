defmodule Hexdocs.Debouncer do
  use GenServer

  @timeout 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], Keyword.take(opts, [:name]))
  end

  def debounce(server, key, timeout, fun) do
    case GenServer.call(server, {:debounce, key}, @timeout) do
      :go ->
        result = {:ok, fun.()}
        Process.send_after(server, {:deadline, key}, timeout)
        result

      :debounced ->
        :debounced
    end
  end

  @impl true
  def init([]) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:debounce, key}, from, state) do
    case Map.fetch(state, key) do
      {:ok, froms} ->
        state = Map.put(state, key, [from | froms])
        {:noreply, state}

      :error ->
        state = Map.put(state, key, [])
        {:reply, :go, state}
    end
  end

  @impl true
  def handle_info({:deadline, key}, state) do
    froms = Map.fetch!(state, key)

    if froms == [] do
      {:noreply, Map.delete(state, key)}
    else
      {debounce, go} = Enum.split(froms, -1)
      Enum.each(debounce, &GenServer.reply(&1, :debounced))
      Enum.each(go, &GenServer.reply(&1, :go))

      state = Map.put(state, key, [])
      {:noreply, state}
    end
  end
end
