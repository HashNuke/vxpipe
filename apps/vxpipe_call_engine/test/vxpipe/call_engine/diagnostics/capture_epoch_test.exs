defmodule Vxpipe.CallEngine.Diagnostics.CaptureEpochTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{SettingsProjection, SettingsSupervisor}
  @projection __MODULE__.Projection
  @reader __MODULE__.Reader

  test "publishing a refresh after observed expiry cannot resurrect the old grant" do
    parent = self()
    clock = :atomics.new(2, signed: true)

    read_clock = fn ->
      sampled_at = :atomics.get(clock, 1)

      if self() == Process.whereis(@projection) and :atomics.get(clock, 2) > 0 and
           :atomics.sub_get(clock, 2, 1) == 0 do
        send(parent, {:clock_sampled, self()})

        receive do
          :release_clock -> :ok
        end
      end

      sampled_at
    end

    loader = fn ->
      send(parent, {:read_started, self()})

      receive do
        {:read_result, result} -> result
      end
    end

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Pool,
       projection: @projection,
       reader: @reader,
       loader: loader,
       clock: read_clock,
       send_after: fn target, message, _delay ->
         send(parent, {:scheduled, target, message})
         make_ref()
       end}
    )

    assert_receive {:read_started, reader}
    send(reader, {:read_result, {:ok, %{enabled: true, revision: 1}}})
    _ = :sys.get_state(reader)
    _ = :sys.get_state(@projection)
    assert {:ok, original_grant} = SettingsProjection.grant(@projection)

    :atomics.put(clock, 1, 2_000)
    assert_receive {:scheduled, target, {:poll, _} = poll}
    send(target, poll)
    assert_receive {:read_started, ^reader}
    :atomics.put(clock, 1, 2_999)
    # Pause publication after its monotonic clock was sampled, modeling preemption.
    :atomics.put(clock, 2, 2)
    send(reader, {:read_result, {:ok, %{enabled: true, revision: 1}}})
    assert_receive {:clock_sampled, projection}
    :atomics.put(clock, 1, 3_000)
    assert {:error, :unavailable} = SettingsProjection.grant(@projection)
    send(projection, :release_clock)
    _ = :sys.get_state(@projection)
    # A publication already in flight may remain unavailable until the next read.
    refute SettingsProjection.grant(@projection) == {:ok, original_grant}
    :atomics.put(clock, 1, 4_000)
    assert_receive {:scheduled, target, {:poll, _} = poll}
    send(target, poll)
    assert_receive {:read_started, ^reader}
    send(reader, {:read_result, {:ok, %{enabled: true, revision: 1}}})
    _ = :sys.get_state(reader)
    _ = :sys.get_state(@projection)
    assert {:ok, renewed_grant} = SettingsProjection.grant(@projection)
    refute renewed_grant == original_grant
  end
end
