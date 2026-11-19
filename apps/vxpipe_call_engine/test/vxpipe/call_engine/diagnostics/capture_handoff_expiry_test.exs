defmodule Vxpipe.CallEngine.Diagnostics.CaptureHandoffExpiryTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsProjection, SettingsSupervisor}
  @projection __MODULE__.Projection
  @reader __MODULE__.Reader

  test "queued capture cannot resume after unobserved authority expiry" do
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
    assert {:ok, _original_grant} = SettingsProjection.grant(@projection)
    assert {:ok, handoff} = CaptureHandoff.new(self(), projection: @projection)
    assert :ok = CaptureHandoff.offer(handoff, {:reset, 1, :audio_gap, 0})
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = queued

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
    # No reader consults the expired lease before delayed publication resumes.
    send(projection, :release_clock)
    _ = :sys.get_state(@projection)
    assert {:error, :revoked} = CaptureHandoff.message(handoff, queued)
    assert %{pending_count: 0, open?: false, discarded: 1} = CaptureHandoff.stats(handoff)
  end
end
