defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeechTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    TextOutput
  }

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.RoomAuthority.{SpeechToSpeech, State}

  @tenant "tenant-sts-room"
  @room "room-sts-room"
  @incarnation "incarnation-sts-room"
  @human "human-sts"
  @agent "agent-sts"
  @human_connection "conn-human-sts"

  test "STS input transcript publishes a caller transcription and agent turn publishes agent text plus completion" do
    state = state()
    capability = self()

    state = caller_transcript(state, "HELLO", "turn-1")

    assert_receive {:vxpipe_event, %_{text: "HELLO", participant_id: @human}}

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-1")

    state =
      SpeechToSpeech.handle_agent_transcript(
        state,
        capability,
        @agent,
        "RECEIVED HELLO",
        "turn-1",
        20
      )

    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED HELLO", participant_id: @agent}}

    state = SpeechToSpeech.handle_turn_completed(state, capability, @agent, "turn-1")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: @agent}}
    assert state.next_sequence > 1
  end

  test "STS reference turn values from capability events do not raise" do
    state = state()
    capability = self()
    turn = make_ref()

    state = caller_transcript(state, "HELLO", turn)
    assert_receive {:vxpipe_event, %_{text: "HELLO", participant_id: @human}}

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, turn)

    state =
      SpeechToSpeech.handle_agent_transcript(
        state,
        capability,
        @agent,
        "RECEIVED HELLO",
        turn,
        20
      )

    assert_receive {:vxpipe_event, %TextOutput{text: "RECEIVED HELLO", participant_id: @agent}}

    state = SpeechToSpeech.handle_turn_completed(state, capability, @agent, turn)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: @agent}}
    assert state.next_sequence > 1
  end

  test "STS interruption publishes an agent turn interruption with the local egress estimate" do
    state = state()
    capability = self()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-9")

    state =
      SpeechToSpeech.handle_interrupted(state, capability, @agent, "turn-9", 120, :no_prefix)

    assert_receive {:vxpipe_event, %AgentTurnInterrupted{played_ms: 120, participant_id: @agent}}
    assert state.sts_turns == %{}
  end

  test "foreign STS capability messages are ignored" do
    state = state()
    other = spawn(fn -> :ok end)

    unchanged = SpeechToSpeech.handle_turn_started(state, other, @agent, "turn-x")
    assert unchanged == state
    refute_received {:vxpipe_event, _event}
  end

  test "STS tool calls publish agent-attributed tool events" do
    state =
      state()
      |> with_plan(%{"echo" => %{name: "echo", type: :mcp, conversation_mode: :non_blocking}})

    capability = self()
    call_ref = make_ref()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-tool")

    state =
      SpeechToSpeech.handle_tool_call(state, capability, @agent, call_ref, "turn-tool", "echo", %{
        "text" => "hi"
      })

    assert_receive {:vxpipe_event, %_{name: "echo", participant_id: @agent}}

    state = SpeechToSpeech.handle_tool_cancelled(state, capability, @agent, call_ref)
    assert_receive {:vxpipe_event, %_{participant_id: @agent}}
    assert state.next_sequence > 1
  end

  test "STS tool calls outside the agent allowlist fail closed without execution" do
    stub = start_supervised!({Vxpipe.CallEngine.STSToolResultReceiver, self()})
    state = state() |> with_plan(%{}) |> bind_capability(stub, @agent)
    capability = stub
    call_ref = make_ref()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-tool")

    state =
      SpeechToSpeech.handle_tool_call(
        state,
        capability,
        @agent,
        call_ref,
        "turn-tool",
        "evil",
        %{}
      )

    assert_receive {:vxpipe_event,
                    %Vxpipe.CallEngine.Event.ToolCallFailed{
                      name: "evil",
                      reason: :unauthorized,
                      participant_id: @agent
                    }}

    refute_received {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{}}
    assert state.sts_tool_calls == %{}
    assert_receive {:provider_tool_result, ^call_ref, %{"error" => "tool_failed"}}
  end

  test "STS blocking host tools execute within bounds and complete through the room" do
    tools = %{
      "get_current_time" => %{
        name: "get_current_time",
        type: :host,
        conversation_mode: :blocking,
        action: Vxpipe.CallEngine.Tool.CurrentTime
      }
    }

    state = state() |> with_plan(tools)
    stub = start_supervised!({Vxpipe.CallEngine.STSToolResultReceiver, self()})
    state = bind_capability(state, stub, @agent)
    capability = stub
    call_ref = make_ref()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-tool")

    state =
      SpeechToSpeech.handle_tool_call(
        state,
        capability,
        @agent,
        call_ref,
        "turn-tool",
        "get_current_time",
        %{}
      )

    assert_receive {:vxpipe_event,
                    %Vxpipe.CallEngine.Event.ToolCallStarted{name: "get_current_time"}}

    assert_receive {:vxpipe_sts_tool_executed, ^capability, ^call_ref, {:ok, result}}, 1_000
    assert result["timezone"] == "UTC"

    state = SpeechToSpeech.handle_tool_executed(state, capability, call_ref, {:ok, result})

    assert_receive {:vxpipe_event,
                    %Vxpipe.CallEngine.Event.ToolCallCompleted{
                      name: "get_current_time",
                      participant_id: @agent
                    }}

    assert state.sts_tool_calls == %{}
    assert_receive {:provider_tool_result, ^call_ref, ^result}
  end

  test "STS tool cancellation settles pending calls and late results are ignored" do
    state =
      state()
      |> with_plan(%{"echo" => %{name: "echo", type: :mcp, conversation_mode: :non_blocking}})

    stub = start_supervised!({Agent, fn -> :ok end})
    state = bind_capability(state, stub, @agent)
    capability = stub
    call_ref = make_ref()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-tool")

    state =
      SpeechToSpeech.handle_tool_call(
        state,
        capability,
        @agent,
        call_ref,
        "turn-tool",
        "echo",
        %{}
      )

    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallStarted{}}
    assert Map.has_key?(state.sts_tool_calls, call_ref)

    state = SpeechToSpeech.handle_tool_cancelled(state, capability, @agent, call_ref)
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallCancelled{}}
    assert state.sts_tool_calls == %{}

    unchanged = SpeechToSpeech.handle_tool_executed(state, capability, call_ref, {:ok, %{}})
    assert unchanged == state
    refute_received {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallCompleted{}}
  end

  test "live microphone audio offered through the room reaches the real STS allocation" do
    {_tree, capability} = start_real_capability()
    state = state() |> bind_capability(capability, @agent)
    {:ok, pcm} = morse_pcm("HI")

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = SpeechToSpeech.offer_audio(state, @human_connection, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = SpeechToSpeech.offer_audio(state, @human_connection, tail)
    end

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{
                      identity: %{participant_id: @human},
                      event: %{kind: :input_transcript, text: "HI", final: true}
                    }}
  end

  test "partial caller transcripts publish without settling history" do
    state = state()
    before = state.spoken_history

    state =
      caller_transcript(state, "HE", "turn-p", false)

    assert_receive {:vxpipe_event, %ParticipantTranscription{text: "HE", final: false}}
    assert state.spoken_history == before

    state =
      caller_transcript(state, "HELLO", "turn-p", true)

    assert_receive {:vxpipe_event, %ParticipantTranscription{text: "HELLO", final: true}}
    assert state.spoken_history != before
  end

  test "STS usage source resolves with activation for observation attribution" do
    stub = start_supervised!({Agent, fn -> :ok end})
    state = state() |> bind_capability(stub, @agent, "activation-sts")

    assert {:ok, %{participant_id: @agent, activation_id: "activation-sts"}} =
             Vxpipe.CallEngine.RoomAuthority.UsageSource.resolve(state, stub)
  end

  test "authorized STS usage observations pass the room boundary" do
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Usage, as: STSUsage
    alias Vxpipe.CallEngine.RoomAuthority.UsageObservations

    stub = start_supervised!({Agent, fn -> :ok end})
    state = state() |> bind_capability(stub, @agent, "activation-sts")

    context = %{
      tenant_id: @tenant,
      call_id: "call-1",
      room_id: @room,
      incarnation_id: @incarnation,
      participant_id: @agent,
      activation_id: "activation-sts"
    }

    descriptor = %{
      usage_identity: %{provider: :morse_code, model: "morse", provenance: :locally_measured}
    }

    [observation] =
      STSUsage.turn_observations(context, descriptor, make_ref(), :succeeded, 20, 0, false)

    recorded = UsageObservations.record(state, stub, [observation])
    assert %_{} = recorded

    other = spawn(fn -> :ok end)
    assert UsageObservations.record(state, other, [observation]) == state
  end

  test "STS allocation requires an available policy authority" do
    state = state()
    assert SpeechToSpeech.allocation_policy(state) == {:error, :media_policy_unavailable}
    assert state.speech_to_speech_policy_revision == 0

    authority = start_supervised!({Agent, fn -> :unused end})
    monitor = Process.monitor(authority)
    stop_supervised!(Agent)
    assert_receive {:DOWN, ^monitor, :process, ^authority, _}

    assert SpeechToSpeech.allocation_policy(%{state | media_policy_authority: authority}) ==
             {:error, :media_policy_unavailable}
  end

  test "provider speech onset through the room never publishes twice" do
    stub = start_supervised!({Agent, fn -> :ok end})
    state = state() |> bind_capability(stub, @agent)
    turn = make_ref()

    assert SpeechToSpeech.handle_speech_started(state, stub, @agent, turn) == state
    refute_received {:vxpipe_event, _event}

    other = spawn(fn -> :ok end)
    assert SpeechToSpeech.handle_speech_started(state, other, @agent, turn) == state
  end

  test "a delayed room speech-onset notification cannot cancel the reply it triggered" do
    {_tree, capability} = start_real_capability()
    state = state() |> bind_capability(capability, @agent)
    {:ok, pcm} = morse_pcm("HI")

    for chunk <- pcm_chunks(pcm) do
      assert :ok = SpeechToSpeech.offer_audio(state, @human_connection, chunk)
    end

    assert_receive {:vxpipe_sts_speech_started, ^capability, @agent, turn}
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^turn}
    assert_receive {:test_audio_output_finish, sink, _sink_turn}, 5_000

    assert SpeechToSpeech.handle_speech_started(state, capability, @agent, turn) == state
    refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _}
    Vxpipe.CallEngine.TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    Vxpipe.CallEngine.TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn}, 1_000
    refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _}
  end

  test "STS transfer hold and release work without any text capability" do
    {_tree, capability} = start_real_capability()
    state = state() |> bind_capability(capability, @agent)
    assert state.text_capability == nil

    held = SpeechToSpeech.hold(state)
    assert held.speech_to_speech_capability != nil
    assert held.speech_to_speech_capability.input_epoch == nil
    assert held.sts_caller_turns == %{}
    assert :sys.get_state(capability).held?

    released = SpeechToSpeech.release(held)
    assert is_reference(released.speech_to_speech_capability.input_epoch)

    assert :sys.get_state(capability).input_epoch ==
             released.speech_to_speech_capability.input_epoch

    refute :sys.get_state(capability).held?
    assert released.speech_to_speech_capability != nil

    assert %_{} = SpeechToSpeech.release(%{state | speech_to_speech_capability: nil})
  end

  test "STS hold, interrupt and stop are safe with no allocation and usage resolves the STS source" do
    state = state()
    capability = self()

    assert SpeechToSpeech.ready?(state) == false
    assert SpeechToSpeech.current?(state, capability) == true

    unbound = %{
      state
      | speech_to_speech_capability: Map.delete(state.speech_to_speech_capability, :input_handle)
    }

    assert SpeechToSpeech.handle_ready(unbound, capability) == unbound
    assert SpeechToSpeech.ready?(unbound) == false

    assert {:ok, _state} = SpeechToSpeech.interrupt(%{state | speech_to_speech_capability: nil})
    assert %_{} = SpeechToSpeech.hold(%{state | speech_to_speech_capability: nil})
    assert %_{} = SpeechToSpeech.stop(%{state | speech_to_speech_capability: nil})

    assert {:ok, %{participant_id: @agent}} =
             Vxpipe.CallEngine.RoomAuthority.UsageSource.resolve(state, capability)
  end

  defp state do
    recorder = %Recorder{port: nil, participant_activations: %{@agent => "activation-sts"}}

    snapshot = %RoomSnapshot{
      tenant_id: @tenant,
      room_id: @room,
      incarnation_id: @incarnation,
      lifecycle: :open,
      created_by_actor_id: "actor-sts",
      created_by_command_id: "command-sts"
    }

    base = State.new(recorder, snapshot, %{})

    {:ok, command} =
      Vxpipe.CallEngine.Command.AttachConnection.new(
        tenant_id: @tenant,
        actor_id: "actor-sts",
        room_id: @room,
        incarnation_id: @incarnation,
        participant_id: @human,
        connection_id: @human_connection,
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )

    connections = %{
      @human_connection => %{
        participant_id: @human,
        pid: self(),
        role: :human,
        admission: :main,
        attach_command: command
      }
    }

    %{base | connections: connections, transcript_router: nil}
    |> bind_capability(self(), @agent)
  end

  defp caller_transcript(state, text, turn, final? \\ true) do
    alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
    alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.CallerTurns
    alias Vxpipe.CallEngine.Speech.Event

    policy = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new([@human, @agent]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: false,
        save_transcripts: false
      }
    }

    evidence = %{
      identity: state.speech_to_speech_capability.input_handle.identity,
      epoch: state.speech_to_speech_capability.input_epoch,
      audio_interval: 0,
      transcript_interval: 0
    }

    {:ok, state} =
      CallerTurns.handle(
        state,
        self(),
        Map.put(evidence, :event, %Event{
          kind: :speech_started,
          turn_ref: turn,
          sequence: state.sts_caller_sequence + 1
        }),
        policy
      )

    {:ok, state} =
      CallerTurns.handle(
        state,
        self(),
        Map.put(evidence, :event, %Event{
          kind: :input_transcript,
          turn_ref: turn,
          sequence: state.sts_caller_sequence + 1,
          text: text,
          final: final?
        }),
        policy
      )

    state
  end

  defp bind_capability(state, capability, agent_id, activation_id \\ nil) do
    state = SpeechToSpeech.bind_capability(state, capability, agent_id, activation_id)
    source = Map.fetch!(state.connections, @human_connection)

    binding =
      Map.merge(state.speech_to_speech_capability, %{
        connection_id: @human_connection,
        connection: source.pid,
        input_epoch: make_ref(),
        input_handle: Vxpipe.CallEngine.STSInputHandle.new(source.attach_command, source.pid)
      })

    %{state | speech_to_speech_capability: binding}
  end

  defp start_real_capability do
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech, as: Capability
    alias Vxpipe.CallEngine.MediaPolicy.Effective
    alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
    alias Vxpipe.CallEngine.Speech.PrivateInit

    sink =
      start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, [observer: self()]},
        id: make_ref()
      )

    {:ok, private_init} = PrivateInit.open([], 5_000)

    tree =
      start_supervised!(
        Supervisor.child_spec(
          {Capability.Tree,
           [
             owner: self(),
             agent_id: @agent,
             human_id: @human,
             provider: {Vxpipe.Providers.MorseCode.STSSession, []},
             provider_private: private_init,
             sink: sink,
             frame_identity: %{},
             caller_source: :sts,
             policy: %Effective{
               audio_routes: :unrestricted,
               transcript_routes: :unrestricted,
               record_audio: true,
               save_transcripts: true
             }
           ]},
          id: make_ref()
        )
      )

    capability = Capability.Tree.capability(tree)
    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
    {tree, capability}
  end

  defp morse_pcm(text) do
    alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
    {:ok, config} = Config.new([])
    Encoder.encode(config, text)
  end

  defp pcm_chunks(<<chunk::binary-size(320), rest::binary>>), do: [chunk | pcm_chunks(rest)]
  defp pcm_chunks(<<>>), do: []
  defp pcm_chunks(tail), do: [tail]

  defp with_plan(state, tools) do
    plan = %{
      participants: %{
        "agent-key" => %{
          kind: :agent,
          participant_id: @agent,
          activation_id: "activation-sts",
          tools: tools
        }
      },
      entry_caller: "human-key"
    }

    %{state | participant_transfer_runtime: %{plan: plan, startup_options: []}}
  end
end
