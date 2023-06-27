defmodule Hexdocs.Debouncer do
  use GenServer

  @timeout 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], Keyword.take(opts, [:name]))
  end

  def debounce(server, key, timeout, fun) do
    case GenServer.call(server, {:debounce, key, timeout}, @timeout) do
      :go ->
        {:ok, fun.()}

      :debounced ->
        :debounced
    end
  end

  @impl true
  def init([]) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:debounce, key, timeout}, from, state) do
    case Map.fetch(state, key) do
      {:ok, froms} ->
        state = Map.put(state, key, [from | froms])
        {:noreply, state}

      :error ->
        state = Map.put(state, key, [])
        send_deadline(key, timeout)
        {:reply, :go, state}
    end
  end

  @impl true
  def handle_info({:deadline, key, timeout}, state) do
    froms = Map.fetch!(state, key)

    if froms == [] do
      {:noreply, Map.delete(state, key)}
    else
      {debounce, go} = Enum.split(froms, -1)
      Enum.each(debounce, &GenServer.reply(&1, :debounced))
      Enum.each(go, &GenServer.reply(&1, :go))
      send_deadline(key, timeout)
      state = Map.put(state, key, [])
      {:noreply, state}
    end
  end

  defp send_deadline(key, timeout) do
    Process.send_after(self(), {:deadline, key, timeout}, timeout)
  end
end
