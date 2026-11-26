defmodule Vxpipe.Gateway.Media.EgressAcceptanceRevocationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.Gateway.Media.EgressAcceptance

  @identity %{
    tenant_id: "tenant-revoke",
    room_id: "room-revoke",
    incarnation_id: "incarnation-revoke"
  }

  test "stale handoff queues nothing on the actual gateway path; private briefing never records" do
    handoff = handoff("connection-permitted")

    # Participant-origin private briefing: never recorded.
    assert :ok =
             EgressAcceptance.record(
               handoff,
               current("agent", :private, :participant),
               "connection-permitted",
               payload()
             )

    refute_receive {:vxpipe_recording_egress, ^handoff, _frame}

    # Room-origin private asset: recorded while the credential is live.
    assert :ok =
             EgressAcceptance.record(
               handoff,
               current("caller", :private, :room),
               "connection-permitted",
               payload()
             )

    assert_receive {:vxpipe_recording_egress, ^handoff, %{origin: :room}}

    # Detached/failed credential: the same gateway path queues nothing.
    :ok = EgressHandoff.invalidate(handoff)

    assert :ok =
             EgressAcceptance.record(
               handoff,
               current("caller", :private, :room),
               "connection-permitted",
               payload()
             )

    refute_receive {:vxpipe_recording_egress, ^handoff, _frame2}, 100
    :ok = EgressHandoff.release(handoff)
  end

  defp current(source, scope, origin) do
    Map.merge(@identity, %{source_participant_id: source, audio_scope: scope, origin: origin})
  end

  defp handoff(connection_id) do
    counters = EgressHandoff.new_counters()
    :ok = EgressHandoff.install_policy(counters, 0, true)

    EgressHandoff.new(
      self(),
      make_ref(),
      @identity,
      %{
        channels: 1,
        clock: fn -> 0 end,
        clock_origin_ms: 0,
        frame_samples: 960,
        gate: counters,
        sample_rate: 48_000
      },
      connection_id,
      4,
      counters
    )
  end

  defp payload, do: :binary.copy(<<1, 0>>, 960)
end
