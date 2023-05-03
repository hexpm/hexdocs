defmodule Hexdocs.DebouncerTest do
  use ExUnit.Case, async: true
  alias Hexdocs.Debouncer

  @short_grace_time 10
  @grace_time 100
  @long_grace_time 10000

  setup do
    {:ok, pid} = Debouncer.start_link()
    %{pid: pid}
  end

  test "zero same key", %{pid: pid} do
    self = self()

    assert {:ok, _} = Debouncer.debounce(pid, :key, 0, send_fun(self, :msg1))
    Process.sleep(@short_grace_time)
    assert {:ok, _} = Debouncer.debounce(pid, :key, 0, send_fun(self, :msg2))
    Process.sleep(@short_grace_time)
    assert {:ok, _} = Debouncer.debounce(pid, :key, 0, send_fun(self, :msg3))

    now = System.monotonic_time(:millisecond)
    assert_receive_within(:msg1, now, 0)
    assert_receive_within(:msg2, now, 0)
    assert_receive_within(:msg3, now, 0)
  end

  test "zero different keys", %{pid: pid} do
    self = self()

    run_stream([
      fn -> assert {:ok, _} = Debouncer.debounce(pid, :a, 500, send_fun(self, :msg1)) end,
      fn -> assert {:ok, _} = Debouncer.debounce(pid, :b, 500, send_fun(self, :msg2)) end,
      fn -> assert {:ok, _} = Debouncer.debounce(pid, :c, 500, send_fun(self, :msg3)) end
    ])

    now = System.monotonic_time(:millisecond)
    assert_receive_within(:msg1, now, 0)
    assert_receive_within(:msg2, now, 0)
    assert_receive_within(:msg3, now, 0)
  end

  test "debounce same key", %{pid: pid} do
    self = self()

    run_stream([
      fn -> assert {:ok, _} = Debouncer.debounce(pid, :key, 500, send_fun(self, :msg1)) end,
      fn -> assert {:ok, _} = Debouncer.debounce(pid, :key, 500, send_fun(self, :msg2)) end,
      fn -> assert :debounced = Debouncer.debounce(pid, :key, 500, send_fun(self, :msg3)) end,
      fn -> assert :debounced = Debouncer.debounce(pid, :key, 500, send_fun(self, :msg4)) end
    ])

    now = System.monotonic_time(:millisecond)
    assert_receive_within(:msg1, now, 0)
    assert_receive_within(:msg2, now, 500)
    refute_receive :msg3
    refute_receive :msg4
  end

  defp assert_receive_within(message, from, time) do
    assert_receive ^message, @long_grace_time
    now = System.monotonic_time(:millisecond)

    if now >= from + time - @grace_time and now <= from + time + @grace_time do
    else
      flunk("deadline exceeded, diff: #{from + time - now}ms")
    end
  end

  defp send_fun(pid, message) do
    fn -> Process.send(pid, message, []) end
  end

  defp run_stream(enum) do
    Enum.each(enum, fn fun ->
      Task.start(fun)
      Process.sleep(@short_grace_time)
    end)
  end
end
