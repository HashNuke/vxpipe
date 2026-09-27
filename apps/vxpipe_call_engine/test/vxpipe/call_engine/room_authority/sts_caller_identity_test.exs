defmodule Vxpipe.CallEngine.RoomAuthority.STSCallerIdentityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted
  }

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.RoomAuthority
  alias Vxpipe.CallEngine.RoomAuthority.{SpeechToSpeech, State}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.CallerTurns
  alias Vxpipe.CallEngine.Speech.Event
  alias Vxpipe.CallEngine.STSInputHandle
  alias Vxpipe.CallEngine.TranscriptRouter

  @identity %{
    tenant_id: "tenant",
    room_id: "room",
    incarnation_id: "incarnation",
    participant_id: "human",
    connection_id: "source"
  }

  test "room history barrier acknowledges only the current speech capability" do
    state = state()
    reference = make_ref()

    assert {:noreply, ^state} =
             RoomAuthority.handle_info(
               {:vxpipe_sts_reseed_room_barrier, self(), reference},
               state
             )

    assert_receive {:vxpipe_sts_reseed_room_ready, room, ^reference}
    assert room == self()

    retired = %{state | speech_to_speech_capability: nil}

    assert {:noreply, ^retired} =
             RoomAuthority.handle_info(
               {:vxpipe_sts_reseed_room_barrier, self(), make_ref()},
               retired
             )

    refute_received {:vxpipe_sts_reseed_room_ready, _, _}
  end

  for kind <- [:reference, :binary] do
    test "#{kind} provider identity stays private through late final caller text" do
      state = state()
      turn = if unquote(kind) == :reference, do: make_ref(), else: "private-turn"
      start = evidence(state, :speech_started, turn, 1)
      state = handle(state, start)
      assert_receive {:vxpipe_event, %ParticipantTurnStarted{} = started}
      assert String.starts_with?(started.correlation_id, "turn_")
      assert String.starts_with?(started.command_id, "cmd_")
      assert started.correlation_id != inspect(turn)
      assert started.correlation_id != turn

      state = handle(state, evidence(state, :turn_ended, turn, 2))
      assert_receive {:vxpipe_event, %ParticipantTurnCompleted{} = completed}
      assert_same_turn(started, completed)

      state =
        handle(state, evidence(state, :input_transcript, turn, 3, text: "HELLO", final: true))

      assert_receive {:vxpipe_event, %ParticipantTranscription{text: "HELLO", final: true} = text}
      assert_receive {:vxpipe_sts_published_history, _, {:caller, "HELLO"}}
      assert_same_turn(started, text)
      assert state.sts_caller_turns == %{}
      assert handle(state, start) == state
      refute_received {:vxpipe_event, _}
    end
  end

  test "duplicates and transcript-only evidence do not invent another caller turn" do
    state = state()

    assert handle(
             state,
             evidence(state, :input_transcript, "unknown", 1, text: "NO", final: true)
           ).sts_caller_turns == %{}

    refute_received {:vxpipe_event, _}
    state = handle(state, evidence(state, :speech_started, "turn", 2))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{} = started}
    state = handle(state, evidence(state, :speech_started, "turn", 3))
    state = handle(state, evidence(state, :input_transcript, "turn", 4, text: "HE", final: false))
    assert_receive {:vxpipe_event, %ParticipantTranscription{final: false} = partial}
    assert_same_turn(started, partial)

    state =
      handle(state, evidence(state, :input_transcript, "turn", 5, text: "HELLO", final: true))

    assert_receive {:vxpipe_event, %ParticipantTranscription{final: true}}

    state =
      handle(state, evidence(state, :input_transcript, "turn", 6, text: "HELLO", final: true))

    state = handle(state, evidence(state, :turn_ended, "turn", 7, text: "HELLO"))
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
    _state = handle(state, evidence(state, :turn_ended, "turn", 8))
    refute_received {:vxpipe_event, _}
  end

  test "raw references and identical inspected strings are different private turns" do
    state = state()
    reference = make_ref()
    state = handle(state, evidence(state, :speech_started, reference, 1))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: first}}
    state = handle(state, evidence(state, :speech_started, inspect(reference), 2))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{correlation_id: second}}
    assert first != second
    assert map_size(state.sts_caller_turns) == 2
  end

  test "wrong capability, source, epoch, hold and policy evidence cannot publish" do
    state = state()
    event = evidence(state, :speech_started, "turn", 1)
    other = start_supervised!({Agent, fn -> :unused end})
    assert {:ok, ^state} = CallerTurns.handle(state, other, event, policy())

    assert {:ok, ^state} =
             CallerTurns.handle(
               state,
               self(),
               %{event | identity: %{@identity | connection_id: "other"}},
               policy()
             )

    assert {:ok, ^state} =
             CallerTurns.handle(state, self(), %{event | epoch: make_ref()}, policy())

    held = %{state | held_participant_ids: MapSet.new(["human"])}
    assert {:ok, ^held} = CallerTurns.handle(held, self(), event, policy())
    denied = %{policy() | effective: %{policy().effective | audio_routes: %{}}}
    assert {:ok, ^state} = CallerTurns.handle(state, self(), event, denied)
    assert {:ok, ^state} = CallerTurns.handle(state, self(), event, %{policy() | revision: 2})
    selected_stt = %{state | speech_to_text_runtime: %{"human" => :selected}}
    assert {:ok, ^selected_stt} = CallerTurns.handle(selected_stt, self(), event, policy())
    source = Map.fetch!(state.connections, "source")
    replaced = %{state | connections: %{"source" => %{source | pid: other}}}
    assert {:ok, ^replaced} = CallerTurns.handle(replaced, self(), event, policy())
    refute_received {:vxpipe_event, _}
    refute_received {:vxpipe_sts_published_history, _, _}
  end

  test "a final caller transcript rejected after hold never enters reseed history" do
    state = state()
    turn = make_ref()
    state = handle(state, evidence(state, :speech_started, turn, 1))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}

    held = %{state | held_participant_ids: MapSet.new(["human"])}

    assert {:ok, ^held} =
             CallerTurns.handle(
               held,
               self(),
               evidence(state, :input_transcript, turn, 2, text: "UNHEARD", final: true),
               policy()
             )

    refute_received {:vxpipe_event, %ParticipantTranscription{}}
    refute_received {:vxpipe_sts_published_history, _, _}
  end

  test "a final caller transcript suppressed by the router never enters reseed history" do
    state = %{state() | transcript_router: :missing_transcript_router}
    turn = make_ref()
    state = handle(state, evidence(state, :speech_started, turn, 1))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}

    _state =
      handle(state, evidence(state, :input_transcript, turn, 2, text: "UNDELIVERED", final: true))

    refute_received {:vxpipe_event, %ParticipantTranscription{}}
    refute_received {:vxpipe_sts_published_history, _, _}
  end

  test "a routed final caller transcript reaches the virtual agent's reseed history" do
    router =
      start_supervised!(
        {TranscriptRouter,
         Map.to_list(Map.delete(@identity, :participant_id)) ++
           [maximum_retained_revisions: 8, register: false]}
      )

    assert :ok = Enforcer.apply(router, policy(), 1_000)
    state = %{state() | transcript_router: router}
    turn = make_ref()
    state = handle(state, evidence(state, :speech_started, turn, 1))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}

    _state =
      handle(state, evidence(state, :input_transcript, turn, 2, text: "HEARD", final: true))

    assert_receive {:vxpipe_sts_published_history, _, {:caller, "HEARD"}}
  end

  test "the seventeenth unsettled association fails and settled turns release capacity" do
    state =
      Enum.reduce(1..16, state(), fn sequence, state ->
        state = handle(state, evidence(state, :speech_started, "turn-#{sequence}", sequence))
        assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}
        state
      end)

    assert map_size(state.sts_caller_turns) == 16

    assert {:error, :pending_caller_overflow} =
             CallerTurns.handle(
               state,
               self(),
               evidence(state, :speech_started, "overflow", 17),
               policy()
             )

    state = handle(state, evidence(state, :turn_ended, "turn-1", 18, text: "HI"))
    assert_receive {:vxpipe_event, %ParticipantTranscription{final: true}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
    state = handle(state, evidence(state, :speech_started, "next", 19))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}
    assert map_size(state.sts_caller_turns) == 16
    refute_received {:vxpipe_event, _}
  end

  test "unrelated policy revisions preserve a caller's captured source intervals" do
    state = state()
    {:ok, original} = Snapshot.prepare(policy(), nil)

    {:ok, revised} =
      Snapshot.prepare(
        %{
          original
          | revision: 1,
            intervals: nil,
            present_participant_ids: MapSet.put(original.present_participant_ids, "observer")
        },
        original
      )

    {:ok, state} =
      CallerTurns.handle(state, self(), evidence(state, :speech_started, "turn", 1), original)

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{} = started}

    {:ok, state} =
      CallerTurns.handle(
        state,
        self(),
        evidence(state, :turn_ended, "turn", 2, text: "HI"),
        revised
      )

    assert_receive {:vxpipe_event, %ParticipantTranscription{} = text}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{} = completed}
    assert_same_turn(started, text)
    assert_same_turn(started, completed)
    assert state.sts_caller_turns == %{}
  end

  test "capability replacement retires every caller association" do
    state = state()
    state = handle(state, evidence(state, :speech_started, "turn", 1))
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}
    old = evidence(state, :turn_ended, "turn", 3, text: "OLD")
    other = start_supervised!({Agent, fn -> :unused end})
    state = SpeechToSpeech.bind_capability(state, other, "agent")
    assert state.sts_caller_turns == %{}
    assert {:ok, ^state} = CallerTurns.handle(state, self(), old, policy())
    refute_received {:vxpipe_event, _}
  end

  test "denied caller text cannot leak through turn-end fallback or retain a settled slot" do
    state = state()
    denied = %{policy() | effective: %{policy().effective | transcript_routes: %{}}}
    before = state.spoken_history

    {:ok, state} =
      CallerTurns.handle(state, self(), evidence(state, :speech_started, "turn", 1), denied)

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}

    {:ok, state} =
      CallerTurns.handle(
        state,
        self(),
        evidence(state, :turn_ended, "turn", 2, text: "FORBIDDEN"),
        denied
      )

    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
    refute_received {:vxpipe_event, %ParticipantTranscription{}}
    assert state.spoken_history == before
    assert state.sts_caller_turns == %{}
  end

  test "completed calls retain only the sequence watermark, not retired provider IDs" do
    initial = state()
    old_start = evidence(initial, :speech_started, "turn-1", 1)

    state =
      Enum.reduce(1..100, initial, fn index, state ->
        state = handle(state, evidence(state, :speech_started, "turn-#{index}", index * 2 - 1))
        assert_receive {:vxpipe_event, %ParticipantTurnStarted{}}

        state =
          handle(state, evidence(state, :turn_ended, "turn-#{index}", index * 2, text: "HI"))

        assert_receive {:vxpipe_event, %ParticipantTranscription{final: true}}
        assert_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
        assert state.sts_caller_turns == %{}
        state
      end)

    assert state.sts_caller_sequence == 200
    assert handle(state, old_start) == state
    refute_received {:vxpipe_event, _}
  end

  defp handle(state, event) do
    assert {:ok, state} = CallerTurns.handle(state, self(), event, policy())
    state
  end

  defp evidence(state, kind, turn, sequence, fields \\ []) do
    %{
      event: struct!(Event, [kind: kind, turn_ref: turn, sequence: sequence] ++ fields),
      identity: @identity,
      epoch: state.speech_to_speech_capability.input_epoch,
      audio_interval: 0,
      transcript_interval: 0
    }
  end

  defp assert_same_turn(left, right) do
    assert left.command_id == right.command_id
    assert left.correlation_id == right.correlation_id
    assert left.participant_id == right.participant_id
    assert left.connection_id == right.connection_id
  end

  defp policy do
    %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["human", "agent"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }
  end

  defp state do
    snapshot =
      struct!(
        RoomSnapshot,
        Map.merge(
          Map.take(@identity, [:tenant_id, :room_id, :incarnation_id]),
          %{lifecycle: :open, created_by_actor_id: "actor", created_by_command_id: "command"}
        )
      )

    {:ok, command} =
      AttachConnection.new(
        Map.to_list(@identity) ++
          [actor_id: "actor", deadline: DateTime.add(DateTime.utc_now(), 5, :second)]
      )

    source = %{
      pid: self(),
      participant_id: "human",
      role: :human,
      admission: :main,
      attach_command: command
    }

    state = State.new(%Recorder{port: nil, participant_activations: %{}}, snapshot, %{})

    state =
      SpeechToSpeech.bind_capability(
        %{state | connections: %{"source" => source}},
        self(),
        "agent"
      )

    binding =
      Map.merge(state.speech_to_speech_capability, %{
        connection_id: "source",
        connection: self(),
        input_handle: STSInputHandle.new(command, self()),
        input_epoch: make_ref()
      })

    %{state | speech_to_speech_capability: binding}
  end
end
