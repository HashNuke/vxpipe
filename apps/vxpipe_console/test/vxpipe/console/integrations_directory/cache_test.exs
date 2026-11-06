defmodule Vxpipe.Console.IntegrationsDirectory.CacheTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.Cache

  test "worker capacity exhaustion is a recoverable error, not a cache crash" do
    supervisor = start_supervised!({Task.Supervisor, max_children: 0})
    cache = start_supervised!({Cache, name: nil, task_supervisor: supervisor})
    assert {:error, :busy} = Cache.fetch(:categories, %{}, cache)
    assert {:error, :busy} = Cache.fetch(:categories, %{}, cache)
  end

  test "Console owns the cache and its bounded worker supervisor" do
    assert {_id, supervisor, :supervisor, _modules} =
             Enum.find(Supervisor.which_children(Vxpipe.Console.Supervisor), fn {id, _, _, _} ->
               id == Vxpipe.Console.IntegrationsDirectory.Supervisor
             end)

    assert Enum.any?(Supervisor.which_children(supervisor), fn {id, _, _, _} -> id == Cache end)
  end

  test "coalesces simultaneous requests and reuses a validated public page" do
    owner = self()

    loader = fn request, etag ->
      send(owner, {:load, self(), request.params, etag})

      receive do
        :release -> {:ok, %{body: %{"items" => []}, etag: "revision"}}
      end
    end

    cache = start_cache(loader)
    callers = start_supervised!({Task.Supervisor, []}, id: :callers)
    first = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:categories, %{}, cache) end)
    assert_receive {:load, worker, %{"limit" => 100}, nil}
    :erlang.trace(cache, true, [:receive])
    second = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:categories, %{}, cache) end)
    second_pid = second.pid
    assert_receive {:trace, ^cache, :receive, {:"$gen_call", {^second_pid, _}, _request}}
    :erlang.trace(cache, false, [:receive])
    _ = :sys.get_state(cache)
    send(worker, :release)
    assert {:ok, response} = Task.await(first)
    assert {:ok, ^response} = Task.await(second)
    assert {:ok, ^response} = Cache.fetch(:categories, %{}, cache)
    refute_received {:load, _, _, _}
  end

  test "expired pages revalidate with their ETag and queries never share a page" do
    clock = start_supervised!({Agent, fn -> 0 end})
    owner = self()

    loader = fn request, etag ->
      send(owner, {:load, request.params, etag})
      if etag, do: :not_modified, else: {:ok, %{body: request.params, etag: "revision"}}
    end

    cache = start_cache(loader, clock: fn -> Agent.get(clock, & &1) end, ttl: 10)
    assert {:ok, response} = Cache.fetch(:integrations, %{"q" => "one"}, cache)
    assert_receive {:load, %{"q" => "one"}, nil}
    _ = :sys.get_state(cache)
    Agent.update(clock, fn _ -> 11 end)
    assert {:ok, ^response} = Cache.fetch(:integrations, %{"q" => "one"}, cache)
    assert_receive {:load, %{"q" => "one"}, "revision"}
    assert {:ok, other} = Cache.fetch(:integrations, %{"q" => "two"}, cache)
    refute other == response
    assert_receive {:load, %{"q" => "two"}, nil}
  end

  test "a 304 without a body is retried unconditionally once and never cached" do
    owner = self()

    cache =
      start_cache(fn _, etag ->
        send(owner, {:load, etag})
        :not_modified
      end)

    assert {:error, :invalid_response} = Cache.fetch(:categories, %{}, cache)
    assert_receive {:load, nil}
    assert_receive {:load, nil}
    refute_received {:load, _}
  end

  test "entry bounds evict old pages" do
    owner = self()

    loader = fn request, _ ->
      send(owner, {:load, request.params})

      {:ok, %{body: request.params, etag: nil}}
    end

    cache = start_cache(loader, max_entries: 1)
    assert {:ok, _} = Cache.fetch(:integrations, %{"q" => "one"}, cache)
    assert_receive {:load, %{"q" => "one"}}
    assert {:ok, _} = Cache.fetch(:integrations, %{"q" => "two"}, cache)
    assert_receive {:load, %{"q" => "two"}}
    assert {:ok, _} = Cache.fetch(:integrations, %{"q" => "one"}, cache)
    assert_receive {:load, %{"q" => "one"}}
  end

  test "a failed refresh removes an expired page instead of serving it stale" do
    owner = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    cache =
      start_cache(
        fn _, etag ->
          send(owner, {:load, etag})

          if etag,
            do: {:error, :unavailable},
            else: {:ok, %{body: %{"items" => []}, etag: "revision"}}
        end,
        clock: fn -> Agent.get(clock, & &1) end,
        ttl: 10
      )

    assert {:ok, _} = Cache.fetch(:categories, %{}, cache)
    assert_receive {:load, nil}
    _ = :sys.get_state(cache)
    Agent.update(clock, fn _ -> 11 end)
    assert {:error, :unavailable} = Cache.fetch(:categories, %{}, cache)
    assert_receive {:load, "revision"}
    assert {:ok, _} = Cache.fetch(:categories, %{}, cache)
    assert_receive {:load, nil}
  end

  test "byte bounds evict pages and responses larger than the budget are not cached" do
    owner = self()

    cache =
      start_cache(
        fn request, _ ->
          query = request.params["q"]
          send(owner, {:load, query})
          bytes = if query == "oversize", do: 2000, else: 900
          {:ok, %{body: %{"data" => String.duplicate("x", bytes)}, etag: nil}}
        end,
        max_bytes: 1600,
        max_entries: 10
      )

    assert {:ok, response} = Cache.fetch(:integrations, %{"q" => "one"}, cache)
    assert_receive {:load, "one"}
    assert {:ok, ^response} = Cache.fetch(:integrations, %{"q" => "one"}, cache)
    refute_received {:load, _}

    for query <- ["two", "one", "oversize", "oversize"] do
      assert {:ok, _} = Cache.fetch(:integrations, %{"q" => query}, cache)
      assert_receive {:load, ^query}
    end
  end

  test "worker and waiter limits reject excess callers and recover after completion" do
    owner = self()

    cache =
      start_cache(
        fn _, _ ->
          send(owner, {:load, self()})

          receive do
            :release -> {:ok, %{body: %{"items" => []}, etag: nil}}
          end
        end,
        max_tasks: 1,
        max_waiters: 1
      )

    callers = start_supervised!({Task.Supervisor, []}, id: :bounded_callers)
    first = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:categories, %{}, cache) end)
    assert_receive {:load, worker}
    assert {:error, :busy} = Cache.fetch(:categories, %{}, cache)
    assert {:error, :busy} = Cache.fetch(:integrations, %{}, cache)
    refute_received {:load, _}
    send(worker, :release)
    assert {:ok, _} = Task.await(first)

    next = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:integrations, %{}, cache) end)
    assert_receive {:load, next_worker}
    send(next_worker, :release)
    assert {:ok, _} = Task.await(next)
  end

  @tag :capture_log
  test "worker crashes release the request slot and permit retry" do
    owner = self()

    cache =
      start_cache(
        fn _, _ ->
          send(owner, {:load, self()})

          receive do
            :crash -> exit(:fixture_crash)
            :release -> {:ok, %{body: %{"items" => []}, etag: nil}}
          end
        end,
        max_tasks: 1
      )

    callers = start_supervised!({Task.Supervisor, []}, id: :crash_callers)
    first = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:categories, %{}, cache) end)
    assert_receive {:load, worker}
    monitor = Process.monitor(worker)
    send(worker, :crash)
    assert {:error, :unavailable} = Task.await(first)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :fixture_crash}

    retry = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:categories, %{}, cache) end)
    assert_receive {:load, next_worker}
    send(next_worker, :release)
    assert {:ok, _} = Task.await(retry)
  end

  test "timed out workers terminate and release capacity for the next request" do
    owner = self()

    cache =
      start_cache(
        fn request, _ ->
          if request.params["q"] == "stall" do
            send(owner, {:load, self()})

            receive do
              :release -> {:ok, %{body: %{"items" => []}, etag: nil}}
            end
          else
            {:ok, %{body: %{"items" => []}, etag: nil}}
          end
        end,
        max_tasks: 1,
        timeout: 1000
      )

    callers = start_supervised!({Task.Supervisor, []}, id: :timeout_callers)

    first =
      Task.Supervisor.async_nolink(callers, fn ->
        Cache.fetch(:integrations, %{"q" => "stall"}, cache)
      end)

    assert_receive {:load, worker}
    monitor = Process.monitor(worker)
    assert {:error, :timeout} = Task.await(first, 2000)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert {:ok, _} = Cache.fetch(:categories, %{}, cache)
  end

  test "Retry-After suppresses upstream calls across queries until its deadline" do
    clock = start_supervised!({Agent, fn -> -100_000 end})
    owner = self()

    cache =
      start_cache(
        fn _, _ ->
          send(owner, :upstream_request)
          {:error, {:rate_limited, 12_000}}
        end,
        clock: fn -> Agent.get(clock, & &1) end
      )

    assert {:error, :rate_limited} = Cache.fetch(:integrations, %{"q" => "first"}, cache)
    assert_received :upstream_request
    assert {:error, :rate_limited} = Cache.fetch(:categories, %{}, cache)
    assert {:error, :rate_limited} = Cache.fetch(:integrations, %{"q" => "second"}, cache)
    refute_received :upstream_request
    Agent.update(clock, fn _ -> -88_000 end)
    assert {:error, :rate_limited} = Cache.fetch(:categories, %{}, cache)
    assert_received :upstream_request
  end

  test "a later short rate limit cannot shorten an existing origin cooldown" do
    owner = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    cache =
      start_cache(
        fn request, _ ->
          send(owner, {:request, self(), request.params["q"]})

          receive do
            {:delay, delay} -> {:error, {:rate_limited, delay}}
          end
        end,
        clock: fn -> Agent.get(clock, & &1) end
      )

    callers = start_supervised!({Task.Supervisor, []}, id: :rate_callers)

    first =
      Task.Supervisor.async_nolink(callers, fn ->
        Cache.fetch(:integrations, %{"q" => "first"}, cache)
      end)

    assert_receive {:request, first_worker, "first"}

    second =
      Task.Supervisor.async_nolink(callers, fn ->
        Cache.fetch(:integrations, %{"q" => "second"}, cache)
      end)

    assert_receive {:request, second_worker, "second"}
    send(first_worker, {:delay, 12_000})
    assert {:error, :rate_limited} = Task.await(first)
    send(second_worker, {:delay, 1_000})
    assert {:error, :rate_limited} = Task.await(second)
    Agent.update(clock, fn _ -> 2_000 end)
    third = Task.Supervisor.async_nolink(callers, fn -> Cache.fetch(:categories, %{}, cache) end)
    assert {:error, :rate_limited} = Task.await(third, 1_000)
    refute_received {:request, _, _}
  end

  defp start_cache(loader, options \\ []) do
    supervisor = start_supervised!({Task.Supervisor, []})

    start_supervised!(
      {Cache, Keyword.merge([name: nil, task_supervisor: supervisor, loader: loader], options)}
    )
  end
end
