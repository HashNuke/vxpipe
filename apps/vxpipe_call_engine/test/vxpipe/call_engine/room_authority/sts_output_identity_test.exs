defmodule Vxpipe.CallEngine.RoomAuthority.STSOutputIdentityTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Command.AttachConnection

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{SpeechToSpeech, State}
  alias Vxpipe.CallEngine.STSInputHandle

  @agent "agent"
  @source "source"

  for kind <- [:binary, :reference] do
    test "#{kind} provider IDs stay private across agent speech, text and completion" do
      state = state()
      provider_turn = if unquote(kind) == :binary, do: "private-provider-turn", else: make_ref()
      state = SpeechToSpeech.handle_turn_started(state, self(), @agent, provider_turn)
      assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}
      assert started.correlation_id != to_string_provider(provider_turn)
      assert String.starts_with?(started.correlation_id, "turn_")
      assert String.starts_with?(started.command_id, "cmd_")
      assert started.connection_id == @source

      state =
        SpeechToSpeech.handle_agent_transcript(state, self(), @agent, "HELLO", provider_turn, 20)

      assert_receive {:vxpipe_event, %TextOutput{} = text}
      assert same_turn?(started, text)

      state = SpeechToSpeech.handle_turn_completed(state, self(), @agent, provider_turn)
      assert_receive {:vxpipe_event, %AgentTurnCompleted{} = completed}
      assert same_turn?(started, completed)
      assert state.sts_turns == %{}

      assert SpeechToSpeech.handle_turn_completed(state, self(), @agent, provider_turn) == state

      assert SpeechToSpeech.handle_agent_transcript(
               state,
               self(),
               @agent,
               "LATE",
               provider_turn,
               20
             ) == state

      refute_received {:vxpipe_event, _}
    end
  end

  test "duplicate active starts and final transcripts preserve one public output" do
    state = SpeechToSpeech.handle_turn_started(state(), self(), @agent, "private-turn")
    assert_receive {:vxpipe_event, %AgentSpeechStarted{} = started}
    assert SpeechToSpeech.handle_turn_started(state, self(), @agent, "private-turn") == state
    refute_received {:vxpipe_event, %AgentSpeechStarted{}}

    state =
      SpeechToSpeech.handle_agent_transcript(state, self(), @agent, "HELLO", "private-turn", 20)

    assert_receive {:vxpipe_event, %TextOutput{} = text}
    assert same_turn?(started, text)

    assert SpeechToSpeech.handle_agent_transcript(
             state,
             self(),
             @agent,
             "HELLO",
             "private-turn",
             20
           ) == state

    refute_received {:vxpipe_event, %TextOutput{}}

    state =
      SpeechToSpeech.handle_interrupted(state, self(), @agent, "private-turn", 20, :no_prefix)

    assert_receive {:vxpipe_event, %AgentTurnInterrupted{} = interrupted}
    assert same_turn?(started, interrupted)
    assert state.sts_turns == %{}
    assert SpeechToSpeech.handle_turn_completed(state, self(), @agent, "private-turn") == state
    refute_received {:vxpipe_event, _}
  end

  test "the current capability cannot publish under another agent's identity" do
    state = state()
    assert SpeechToSpeech.handle_turn_started(state, self(), "other-agent", "turn") == state
    refute_received {:vxpipe_event, _}
    state = SpeechToSpeech.handle_turn_started(state, self(), @agent, "turn")
    assert_receive {:vxpipe_event, %AgentSpeechStarted{}}

    assert SpeechToSpeech.handle_agent_transcript(
             state,
             self(),
             "other-agent",
             "TEXT",
             "turn",
             20
           ) == state

    assert SpeechToSpeech.handle_turn_completed(state, self(), "other-agent", "turn") == state

    assert SpeechToSpeech.handle_interrupted(state, self(), "other-agent", "turn", 20, :no_prefix) ==
             state

    refute_received {:vxpipe_event, _}
  end

  test "output uses only the allocation's pinned source even with other connections" do
    state = state()
    other = Map.fetch!(state.connections, @source)

    connections =
      Map.put(state.connections, "aaa-other", %{other | participant_id: "other-human"})

    state =
      SpeechToSpeech.handle_turn_started(
        %{state | connections: connections},
        self(),
        @agent,
        "turn"
      )

    assert_receive {:vxpipe_event, %AgentSpeechStarted{connection_id: @source}}
    assert map_size(state.sts_turns) == 1
  end

  test "missing binding, replaced connection and mismatched incarnation cannot publish" do
    state = state()
    replacement = start_supervised!({Agent, fn -> :unused end})
    source = Map.fetch!(state.connections, @source)

    invalid_states = [
      %{
        state
        | speech_to_speech_capability:
            Map.delete(state.speech_to_speech_capability, :input_handle)
      },
      %{state | connections: Map.put(state.connections, @source, %{source | pid: replacement})},
      %{state | snapshot: %{state.snapshot | incarnation_id: "replacement-incarnation"}}
    ]

    for invalid <- invalid_states do
      assert SpeechToSpeech.handle_turn_started(invalid, self(), @agent, "turn") == invalid
    end

    refute_received {:vxpipe_event, _}
  end

  test "source loss drops late text and safely retires the terminal association" do
    state = SpeechToSpeech.handle_turn_started(state(), self(), @agent, "turn")
    assert_receive {:vxpipe_event, %AgentSpeechStarted{}}
    state = %{state | connections: %{}}

    assert SpeechToSpeech.handle_agent_transcript(state, self(), @agent, "LATE", "turn", 20) ==
             state

    state = SpeechToSpeech.handle_turn_completed(state, self(), @agent, "turn")
    assert state.sts_turns == %{}
    refute_received {:vxpipe_event, _}
  end

  test "replacing an allocation clears its old output associations" do
    state = SpeechToSpeech.handle_turn_started(state(), self(), @agent, "old-turn")
    assert_receive {:vxpipe_event, %AgentSpeechStarted{}}
    replacement = start_supervised!({Agent, fn -> :unused end})
    state = SpeechToSpeech.bind_capability(state, replacement, @agent)
    assert state.sts_turns == %{}
    assert SpeechToSpeech.handle_turn_completed(state, self(), @agent, "old-turn") == state
    refute_received {:vxpipe_event, _}
  end

  defp same_turn?(left, right) do
    left.command_id == right.command_id and left.correlation_id == right.correlation_id and
      left.connection_id == right.connection_id and left.participant_id == right.participant_id
  end

  defp to_string_provider(turn) when is_binary(turn), do: turn
  defp to_string_provider(turn), do: inspect(turn)

  defp state do
    snapshot = %Snapshot{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "command"
    }

    {:ok, command} =
      AttachConnection.new(
        tenant_id: snapshot.tenant_id,
        room_id: snapshot.room_id,
        incarnation_id: snapshot.incarnation_id,
        actor_id: "actor",
        participant_id: "human",
        connection_id: @source,
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
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
      SpeechToSpeech.bind_capability(%{state | connections: %{@source => source}}, self(), @agent)

    binding =
      Map.merge(state.speech_to_speech_capability, %{
        connection_id: @source,
        connection: self(),
        input_handle: STSInputHandle.new(command, self())
      })

    %{state | speech_to_speech_capability: binding}
  end
end
