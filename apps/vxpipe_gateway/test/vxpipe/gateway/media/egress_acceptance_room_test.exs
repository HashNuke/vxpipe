defmodule Vxpipe.Gateway.Media.EgressAcceptanceRoomTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Media.EgressAcceptance
  alias Vxpipe.CallEngine.Recording.EgressHandoff

  @identity %{
    tenant_id: "tenant-room",
    room_id: "room-room",
    incarnation_id: "incarnation-room"
  }

  test "room-origin private is recorded for a permitted interval; participant private and mixed never are" do
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

    # Mixed output: never recorded.
    assert :ok =
             EgressAcceptance.record(
               handoff,
               current("agent", :mixed, :participant),
               "connection-permitted",
               payload()
             )

    refute_receive {:vxpipe_recording_egress, ^handoff, _frame}

    # Room-origin private asset: recorded while the interval permits it.
    assert :ok =
             EgressAcceptance.record(
               handoff,
               current("caller", :private, :room),
               "connection-permitted",
               payload()
             )

    assert_receive {:vxpipe_recording_egress, ^handoff, frame}
    assert frame.origin == :room
    assert frame.source_participant_id == "caller"
    :ok = EgressHandoff.release(handoff)
  end

  test "room-origin private is dropped once the interval denies recording" do
    handoff = denied_handoff("connection-denied")

    assert :ok =
             EgressAcceptance.record(
               handoff,
               current("caller", :private, :room),
               "connection-denied",
               payload()
             )

    refute_receive {:vxpipe_recording_egress, ^handoff, _frame}
  end

  defp current(source, scope, origin) do
    Map.merge(@identity, %{
      source_participant_id: source,
      audio_scope: scope,
      origin: origin
    })
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

  defp denied_handoff(connection_id) do
    counters = EgressHandoff.new_counters()
    :ok = EgressHandoff.install_policy(counters, 1, false)

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
