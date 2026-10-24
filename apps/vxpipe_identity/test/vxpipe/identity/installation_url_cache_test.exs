defmodule Vxpipe.Identity.InstallationURLCacheTest do
  use ExUnit.Case, async: false
  alias Vxpipe.Identity.InstallationURLCache, as: Cache

  @cache __MODULE__.Cache
  @other __MODULE__.Other
  @tasks __MODULE__.Tasks

  setup do
    start_supervised!({Task.Supervisor, name: @tasks})
    :ok
  end

  test "repeated reads, including an unconfigured URL, share one load" do
    owner = self()

    start_cache(fn ->
      send(owner, :loaded)
      {:ok, %{public_url: nil}}
    end)

    assert {:ok, nil} = Cache.fetch(@cache)
    assert_receive :loaded
    for _ <- 1..20, do: assert({:ok, nil} = Cache.fetch(@cache))
    refute_received :loaded
  end

  test "concurrent cold readers share a single in-flight load" do
    owner = self()

    cache =
      start_cache(fn ->
        send(owner, {:loading, self()})
        receive do: (:release -> {:ok, %{public_url: "https://first.example.test"}})
      end)

    first = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, loader}
    readers = for _ <- 1..10, do: Task.async(fn -> Cache.fetch(@cache) end)
    _ = :sys.get_state(cache)
    refute_received {:loading, _}
    send(loader, :release)

    for reader <- [first | readers],
        do: assert({:ok, "https://first.example.test"} = Task.await(reader))

    refute_received {:loading, _}
  end

  test "invalidation discards an older load and releases waiting readers with the new URL" do
    owner = self()

    start_cache(fn ->
      send(owner, {:loading, self()})
      receive do: ({:release, url} -> {:ok, %{public_url: url}})
    end)

    reader = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, old_loader}
    monitor = Process.monitor(old_loader)
    assert :ok = Cache.invalidate(@cache)
    assert_receive {:DOWN, ^monitor, :process, ^old_loader, _}
    assert_receive {:loading, new_loader}
    send(new_loader, {:release, "https://new.example.test"})
    assert {:ok, "https://new.example.test"} = Task.await(reader)
    assert {:ok, "https://new.example.test"} = Cache.fetch(@cache)
  end

  test "expiry fails closed, backs off failed reads, and recovers without caching errors as nil" do
    clock = :atomics.new(1, [])
    owner = self()

    start_cache(
      fn ->
        send(owner, {:loading, self()})
        receive do: ({:result, result} -> result)
      end,
      clock: fn -> :atomics.get(clock, 1) end,
      ttl_ms: 100,
      retry_ms: 10,
      send_after: fn _, _, _ -> make_ref() end
    )

    first = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, loader}
    send(loader, {:result, {:ok, %{public_url: "https://first.example.test"}}})
    assert {:ok, "https://first.example.test"} = Task.await(first)
    :atomics.put(clock, 1, 100)
    expired = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, failed_loader}
    send(failed_loader, {:result, {:error, :unavailable}})
    assert {:error, :unavailable} = Task.await(expired)
    assert {:error, :unavailable} = Cache.fetch(@cache)
    refute_received {:loading, _}
    :atomics.put(clock, 1, 110)
    recovered = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, recovered_loader}
    send(recovered_loader, {:result, {:ok, %{public_url: "https://new.example.test"}}})
    assert {:ok, "https://new.example.test"} = Task.await(recovered)
  end

  test "another instance refreshes through its timer without a local write notification" do
    owner = self()
    source = start_supervised!({Agent, fn -> "https://first.example.test" end})
    loader = fn -> {:ok, %{public_url: Agent.get(source, & &1)}} end

    timer = fn pid, message, delay ->
      send(owner, {:scheduled, pid, message, delay})
      make_ref()
    end

    start_cache(loader, send_after: timer)
    second = start_cache(loader, name: @other, send_after: timer)
    assert {:ok, "https://first.example.test"} = Cache.fetch(@cache)
    assert {:ok, "https://first.example.test"} = Cache.fetch(@other)
    # Discard the initial timer; successful loading schedules a fresh one.
    assert_receive {:scheduled, ^second, {:refresh, _}, 30_000}
    assert_receive {:scheduled, ^second, {:refresh, _} = refresh, 30_000}
    Agent.update(source, fn _ -> "https://new.example.test" end)
    assert :ok = Cache.invalidate(@cache)
    assert {:ok, "https://new.example.test"} = Cache.fetch(@cache)
    assert {:ok, "https://first.example.test"} = Cache.fetch(@other)
    send(second, refresh)
    # The next scheduled refresh acknowledges that the current load completed.
    assert_receive {:scheduled, ^second, {:refresh, _}, 30_000}
    assert {:ok, "https://new.example.test"} = Cache.fetch(@other)
  end

  test "a stalled load is terminated and excess waiters fail without launching more reads" do
    owner = self()

    timer = fn pid, message, delay ->
      send(owner, {:scheduled, pid, message, delay})
      make_ref()
    end

    cache =
      start_cache(
        fn ->
          send(owner, {:loading, self()})
          receive do: (:never -> {:ok, %{public_url: nil}})
        end,
        send_after: timer,
        maximum_waiters: 1
      )

    reader = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, loader}
    monitor = Process.monitor(loader)
    assert {:error, :unavailable} = Cache.fetch(@cache)
    assert_receive {:scheduled, ^cache, {:load_timeout, _} = timeout, 2_000}
    send(cache, timeout)
    assert {:error, :unavailable} = Task.await(reader)
    assert_receive {:DOWN, ^monitor, :process, ^loader, _}
    refute_received {:loading, _}
  end

  test "a cache owner crash also terminates its in-flight database task" do
    owner = self()

    cache =
      start_cache(fn ->
        send(owner, {:loading, self()})
        receive do: (:never -> {:ok, %{public_url: nil}})
      end)

    reader = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, loader}
    monitor = Process.monitor(loader)
    Process.exit(cache, :kill)
    assert {:error, :unavailable} = Task.await(reader)
    assert_receive {:DOWN, ^monitor, :process, ^loader, _}
  end

  test "a killed database task fails waiting reads without killing the cache owner" do
    owner = self()

    start_cache(fn ->
      send(owner, {:loading, self()})
      receive do: (:never -> {:ok, %{public_url: nil}})
    end)

    reader = Task.async(fn -> Cache.fetch(@cache) end)
    assert_receive {:loading, loader}
    Process.exit(loader, :kill)
    assert {:error, :unavailable} = Task.await(reader)
    assert :ok = Cache.invalidate(@cache)
    assert_receive {:loading, _new_loader}
  end

  defp start_cache(loader, options \\ []) do
    options = Keyword.merge([name: @cache, task_supervisor: @tasks, loader: loader], options)
    start_supervised!(Supervisor.child_spec({Cache, options}, id: Keyword.fetch!(options, :name)))
  end
end
