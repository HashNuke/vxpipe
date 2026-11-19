defmodule Vxpipe.CallEngine.Diagnostics.SettingsProjectionTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{SettingsProjection, SettingsSupervisor}
  @projection __MODULE__.Projection
  @reader __MODULE__.Reader

  setup do
    parent = self()
    clock = :atomics.new(1, signed: true)

    loader = fn ->
      send(parent, {:read_started, self()})

      receive do
        {:read_result, result} -> result
      end
    end

    timer = fn target, message, delay ->
      send(parent, {:scheduled, target, message, delay})
      make_ref()
    end

    pool =
      start_supervised!(
        {SettingsSupervisor,
         name: __MODULE__.Pool,
         projection: @projection,
         reader: @reader,
         loader: loader,
         clock: fn -> :atomics.get(clock, 1) end,
         send_after: timer}
      )

    assert_receive {:read_started, reader}
    %{clock: clock, reader: reader, pool: pool}
  end

  test "unknown settings never authorize; status is a direct expiring read even if projector stalls",
       ctx do
    assert {:unavailable, :unknown_settings} = SettingsProjection.status(@projection)
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    assert {:enabled, 1} = SettingsProjection.status(@projection)
    :sys.suspend(@projection)

    try do
      :atomics.put(ctx.clock, 1, 3_000)
      assert {:unavailable, :expired_settings} = SettingsProjection.status(@projection)
    after
      :sys.resume(@projection)
    end
  end

  for enabled <- [true, false] do
    @enabled enabled
    test "status immediately reports invalidation of enabled=#{@enabled} while projection is stalled",
         ctx do
      settle(ctx.reader, {:ok, %{enabled: @enabled, revision: 1}})
      :sys.suspend(@projection)

      try do
        assert :ok = SettingsProjection.invalidate(@projection)
        assert {:error, :unavailable} = SettingsProjection.grant(@projection)
        assert {:unavailable, :invalidated} = SettingsProjection.status(@projection)
      after
        :sys.resume(@projection)
      end

      _ = :sys.get_state(@projection)
      assert {:unavailable, :invalidated} = SettingsProjection.status(@projection)
    end
  end

  test "timeout closes authority and retains the one reader slot until it settles", ctx do
    fire(:read_timeout)
    _ = :sys.get_state(@projection)
    assert {:unavailable, :read_timeout} = SettingsProjection.status(@projection)

    for time <- [1_000, 2_000, 3_000] do
      :atomics.put(ctx.clock, 1, time)
      fire(:poll)
      _ = :sys.get_state(@projection)
    end

    refute_received {:read_started, _}
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    assert {:unavailable, :read_timeout} = SettingsProjection.status(@projection)
    :atomics.put(ctx.clock, 1, 4_000)
    fire(:poll)
    assert_receive {:read_started, reader}
    settle(reader, {:ok, %{enabled: false, revision: 2}})
    assert {:disabled, 2} = SettingsProjection.status(@projection)
  end

  test "a late read is rejected even when its result beats the timeout message", ctx do
    :atomics.put(ctx.clock, 1, 1_000)
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    assert {:unavailable, :read_timeout} = SettingsProjection.status(@projection)
  end

  test "invalidation is coalesced and fences an earlier read result", ctx do
    :sys.suspend(@projection)

    try do
      for _ <- 1..1_000, do: assert(:ok == SettingsProjection.invalidate(@projection))

      assert {:message_queue_len, 1} =
               Process.info(Process.whereis(@projection), :message_queue_len)
    after
      :sys.resume(@projection)
    end

    _ = :sys.get_state(@projection)
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    assert {:unavailable, :invalidated} = SettingsProjection.status(@projection)
    :atomics.put(ctx.clock, 1, 1_000)
    fire(:poll)
    assert_receive {:read_started, reader}
    settle(reader, {:ok, %{enabled: false, revision: 2}})
    assert {:disabled, 2} = SettingsProjection.status(@projection)
  end

  test "read errors revoke the cached enable and cannot fabricate a default", ctx do
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    :atomics.put(ctx.clock, 1, 1_000)
    fire(:poll)
    assert_receive {:read_started, reader}
    settle(reader, {:error, :unavailable})
    assert {:unavailable, :settings_unavailable} = SettingsProjection.status(@projection)
  end

  test "capture grants survive continuous refresh but cannot bridge an expired interval", ctx do
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    assert {:ok, first} = SettingsProjection.grant(@projection)
    :atomics.put(ctx.clock, 1, 1_000)
    fire(:poll)
    assert_receive {:read_started, reader}
    settle(reader, {:ok, %{enabled: true, revision: 1}})
    assert {:ok, ^first} = SettingsProjection.grant(@projection)

    # Nobody queried status during the expired interval. A later successful read
    # must still retire the old capture epoch, even at the same saved revision.
    :atomics.put(ctx.clock, 1, 4_000)
    fire(:poll)
    assert_receive {:read_started, reader}
    settle(reader, {:ok, %{enabled: true, revision: 1}})
    assert {:ok, next} = SettingsProjection.grant(@projection)
    refute next == first
  end

  test "revocation fences capture grants even if the saved revision stays enabled", ctx do
    settle(ctx.reader, {:ok, %{enabled: true, revision: 1}})
    assert {:ok, first} = SettingsProjection.grant(@projection)
    :sys.suspend(@projection)

    try do
      assert :ok = SettingsProjection.invalidate(@projection)
      assert {:error, :unavailable} = SettingsProjection.grant(@projection)
    after
      :sys.resume(@projection)
    end

    _ = :sys.get_state(@projection)
    assert {:error, :unavailable} = SettingsProjection.grant(@projection)
    :atomics.put(ctx.clock, 1, 1_000)
    fire(:poll)
    assert_receive {:read_started, reader}
    settle(reader, {:ok, %{enabled: true, revision: 1}})
    assert {:ok, next} = SettingsProjection.grant(@projection)
    refute next == first
  end

  test "pool teardown removes authority and ends the outstanding reader", ctx do
    monitor = Process.monitor(ctx.reader)
    stop_supervised!({SettingsSupervisor, __MODULE__.Pool})
    assert_receive {:DOWN, ^monitor, :process, _, _}
    assert {:unavailable, :settings_unavailable} = SettingsProjection.status(@projection)
  end

  defp settle(reader, result) do
    send(reader, {:read_result, result})
    _ = :sys.get_state(reader)
    _ = :sys.get_state(@projection)
  end

  defp fire(kind) do
    assert_receive {:scheduled, target, {^kind, _token} = message, 1_000}
    send(target, message)
  end
end
