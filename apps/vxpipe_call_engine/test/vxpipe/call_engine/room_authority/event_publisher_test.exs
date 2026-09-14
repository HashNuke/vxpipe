defmodule Vxpipe.CallEngine.RoomAuthority.EventPublisherTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State}
  alias Vxpipe.CallEngine.TranscriptRouter

  @identity %{
    tenant_id: "tenant-transcript-event",
    room_id: "room-transcript-event",
    incarnation_id: "incarnation-transcript-event"
  }

  test "projects a provider transcript from its source policy revision" do
    router = start_router()
    :ok = apply_policy(router, 0, ["source", "recipient"])
    :ok = apply_policy(router, 1, ["source", "recipient"], transcript_routes: %{})

    state = state(router)
    event = event()

    assert {_state,
            %{
              "media_policy_revision" => 0,
              "save_transcripts" => true
            }} =
             EventPublisher.publish_transcript(
               state,
               self(),
               event,
               media_policy_revision: 0
             )

    refute_receive {:vxpipe_event, ^event}

    assert %{
             "media_policy_revision" => 0,
             "save_transcripts" => true
           } = EventPublisher.transcript_source_policy(state, "source", 0)
  end

  test "denies transcript delivery and archive permission when its policy router is unavailable" do
    router = start_router()
    :ok = apply_policy(router, 0, ["source", "recipient"])
    monitor = Process.monitor(router)
    Process.exit(router, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^router, :killed}

    event = event()

    assert {_state, %{"save_transcripts" => false}} =
             EventPublisher.publish_transcript(state(router), self(), event)

    refute_receive {:vxpipe_event, ^event}
  end

  defp state(router) do
    recorder = %Recorder{port: nil, participant_activations: %{}}

    snapshot = %RoomSnapshot{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      lifecycle: :open,
      created_by_actor_id: "actor-transcript-event",
      created_by_command_id: "command-transcript-event"
    }

    state = State.new(recorder, snapshot, %{})

    connections = %{
      "source-connection" => %{participant_id: "source", pid: self()},
      "recipient-connection" => %{participant_id: "recipient", pid: self()}
    }

    %{state | connections: connections, transcript_router: router}
  end

  defp event do
    %ParticipantTranscription{
      id: "event-transcript",
      sequence: 1,
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      participant_id: "source",
      connection_id: "source-connection",
      command_id: "command-transcript",
      correlation_id: "turn-transcript",
      text: "old interval",
      final: false,
      provider_turn_index: 0,
      occurred_at: ~U[2026-09-11 00:00:00.000Z]
    }
  end

  defp start_router do
    start_supervised!(
      {TranscriptRouter,
       Map.to_list(@identity) ++ [maximum_retained_revisions: 8, register: false]}
    )
  end

  defp apply_policy(router, revision, participants, overrides \\ []) do
    effective =
      struct!(
        Effective,
        Keyword.merge(
          [
            audio_routes: :unrestricted,
            transcript_routes: :unrestricted,
            record_audio: true,
            save_transcripts: true
          ],
          overrides
        )
      )

    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(participants),
      effective: effective
    }

    Enforcer.apply(router, snapshot, 1_000)
  end
end
