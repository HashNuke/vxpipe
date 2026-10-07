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
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Tools, as: STSTools
  alias Vxpipe.CallEngine.Tool.Context

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

    _state = SpeechToSpeech.handle_turn_completed(state, capability, @agent, "turn-1")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{participant_id: @agent}}
    assert state.next_sequence > 1
  end

  # A provider settles a caller turn whose transcript can never be attributed with an empty
  # final (Gemini Live without input transcription, 2026-10-07). It is not caller text.
  test "an empty final settles the caller turn without publishing a transcription" do
    state = caller_transcript(state(), "", "turn-silent")
    refute_received {:vxpipe_event, %ParticipantTranscription{}}
    assert %{final?: true} = Map.fetch!(state.sts_caller_turns, "turn-silent")
  end

  test "only the opening's matching STS playback completion releases opening protection" do
    first = %Vxpipe.CallEngine.RoomAuthority.FirstMessage{
      mode: :fixed,
      status: :started,
      target_participant_id: @human,
      text: "HELLO"
    }

    state = %{state() | first_message: first}
    state = SpeechToSpeech.handle_turn_started(state, self(), @agent, "opening", 1)
    state = SpeechToSpeech.handle_turn_completed(state, self(), @agent, "unknown", 1)
    assert state.first_message.status == :started
    state = SpeechToSpeech.handle_turn_completed(state, self(), @agent, "opening", 2)
    assert state.first_message.status == :started
    state = SpeechToSpeech.handle_turn_completed(state, self(), @agent, "opening", 1)
    assert state.first_message.status == :completed
  end

  # Live GPT-Live run 2026-10-07: the provider session failed after the phone leg attached
  # but before the capability was ready (so before the room monitored it). The room cleared
  # the capability and left the caller in a silent call.
  test "an STS agent lost before it is ready tells attached connections the agent is unavailable" do
    state = state()
    refute state.speech_to_speech_ready?

    state = SpeechToSpeech.handle_unavailable(state, self(), :provider_failed)

    assert state.speech_to_speech_capability == nil
    assert_received {:vxpipe_connection_unavailable, :agent_unavailable}
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

  test "an overlapping caller onset marks the active agent turn :overlapped when it completes" do
    state = state()
    capability = self()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-1")
    state = SpeechToSpeech.handle_speech_started(state, capability, @agent, "turn-2")
    _state = SpeechToSpeech.handle_turn_completed(state, capability, @agent, "turn-1")

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{participant_id: @agent, outcome: :overlapped}}
  end

  test "a non-overlapped agent turn completes as :completed" do
    state = state()
    capability = self()

    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-1")
    _state = SpeechToSpeech.handle_turn_completed(state, capability, @agent, "turn-1")

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{participant_id: @agent, outcome: :completed}}
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

  test "STS interruption publishes an aligned spoken prefix before its terminal event" do
    state = state()
    capability = self()
    state = SpeechToSpeech.handle_turn_started(state, capability, @agent, "turn-prefix")

    state =
      SpeechToSpeech.handle_interrupted(
        state,
        capability,
        @agent,
        "turn-prefix",
        20,
        {:aligned_prefix, "HELLO", 0}
      )

    assert_receive {:vxpipe_event, %TextOutput{text: "HELLO", participant_id: @agent}}
    assert_receive {:vxpipe_event, %AgentTurnInterrupted{played_ms: 20}}
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
    {_tree, capability} = start_real_capability()
    state = bind_capability(state, capability, @agent)
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

    assert_receive {:vxpipe_sts_tool_completion, bridge, lease}, 1_000
    assert {:ok, result} = lease.completion.outcome
    assert result["timezone"] == "UTC"

    state = STSTools.handle_completion(state, bridge, lease)

    assert_receive {:vxpipe_event,
                    %Vxpipe.CallEngine.Event.ToolCallCompleted{
                      name: "get_current_time",
                      participant_id: @agent
                    }}

    assert state.sts_tool_calls == %{}
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

  test "mute hold preserves a room-owned pending tool and delivers its result while held" do
    tools = %{"echo" => %{name: "echo", type: :mcp, conversation_mode: :non_blocking}}
    {_tree, capability} = start_real_capability(duplex?: true)
    state = state() |> with_plan(tools) |> bind_capability(capability, @agent)
    provider = Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session)

    assert :ok =
             Vxpipe.CallEngine.Capability.SpeechToSpeech.push_text(
               capability,
               "TOOL echo {\"text\":\"hi\"}"
             )

    assert_receive {:vxpipe_sts_tool_event, ^capability, @agent,
                    %{event: %{kind: :tool_call, call_ref: call_ref}}}

    state =
      SpeechToSpeech.handle_tool_call(
        state,
        capability,
        @agent,
        call_ref,
        "tool-turn",
        "echo",
        %{}
      )

    assert Map.has_key?(state.sts_tool_calls, call_ref)

    held = SpeechToSpeech.hold(state)
    assert Map.has_key?(held.sts_tool_calls, call_ref)
    assert held.speech_to_speech_capability.input_epoch == nil

    settled =
      SpeechToSpeech.handle_tool_executed(held, capability, call_ref, {:ok, %{"text" => "OK"}})

    assert settled.sts_tool_calls == %{}
    assert_receive {:vxpipe_event, %Vxpipe.CallEngine.Event.ToolCallCompleted{name: "echo"}}
    assert :sys.get_state(provider).held_tool_replies != []
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
      STSUsage.turn_observations(context, descriptor, make_ref(), :succeeded, 20, nil)

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
    assert_receive {:vxpipe_sts_turn_started, ^capability, @agent, ^turn, _}
    assert_receive {:test_audio_output_finish, sink, _sink_turn}, 5_000

    assert SpeechToSpeech.handle_speech_started(state, capability, @agent, turn) == state
    refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _, _}
    Vxpipe.CallEngine.TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    Vxpipe.CallEngine.TestAudioOutputSink.playback_completed(sink)

    assert_receive {:vxpipe_sts_turn_completed, ^capability, @agent, ^turn, _}, 1_000
    refute_received {:vxpipe_sts_interrupted, ^capability, @agent, ^turn, _, _, _}
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

  test "a failed Morse duplex transfer releases the same session and completion stops it" do
    {state, capability, provider, _wire} = start_transfer_provider(:morse)
    monitor = Process.monitor(provider)
    capability_monitor = Process.monitor(capability)

    held = SpeechToSpeech.hold(state)
    assert held.speech_to_speech_capability.input_epoch == nil
    assert :sys.get_state(provider).held?

    released = SpeechToSpeech.release(held)
    assert is_reference(released.speech_to_speech_capability.input_epoch)

    assert Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session) ==
             provider

    refute :sys.get_state(provider).held?
    refute_received {:DOWN, ^monitor, :process, ^provider, _}
    assert :ok = Vxpipe.CallEngine.Capability.SpeechToSpeech.push_text(capability, "HI")

    assert_receive {:vxpipe_sts_input_event, ^capability,
                    %{event: %{kind: :input_transcript, text: "HI", final: true}}},
                   1_000

    held_again = SpeechToSpeech.hold(released)

    completed =
      ParticipantTransfer.teardown_source(held_again, capability, transfer_context(held_again))

    assert completed.speech_to_speech_capability == nil
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}, 1_000
  end

  test "a failed GPT-Live transfer releases the same socket and completion stops it" do
    {state, capability, provider, wire} = start_transfer_provider(:gpt_live)
    monitor = Process.monitor(provider)
    capability_monitor = Process.monitor(capability)

    held = change_gpt_live_hold(state, wire, true)
    assert held.speech_to_speech_capability.input_epoch == nil
    assert :sys.get_state(provider).held?

    released = change_gpt_live_hold(held, wire, false)
    assert is_reference(released.speech_to_speech_capability.input_epoch)

    assert Vxpipe.CallEngine.Speech.Session.provider(:sys.get_state(capability).session) ==
             provider

    refute :sys.get_state(provider).held?
    refute_received {:DOWN, ^monitor, :process, ^provider, _}

    assert :ok =
             Vxpipe.CallEngine.Capability.SpeechToSpeech.push_audio(capability, @human, <<1, 0>>)

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.input_audio.append"}}

    held_again = change_gpt_live_hold(released, wire, true)

    completed =
      ParticipantTransfer.teardown_source(held_again, capability, transfer_context(held_again))

    assert completed.speech_to_speech_capability == nil
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 1_000
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _}, 1_000
    refute_received {:test_gpt_live_started, _, _}
  end

  test "room hold requests the attached WebRTC source cutover asynchronously" do
    {_tree, capability} = start_real_capability()
    peer = start_supervised!({Vxpipe.CallEngine.TestSTSSourceControlPeer, observer: self()})
    attachment = make_ref()
    state = state()
    source = Map.fetch!(state.connections, @human_connection)

    state = %{
      state
      | connections:
          Map.put(
            state.connections,
            @human_connection,
            Map.merge(source, %{
              pid: peer,
              source_control?: true,
              room_monitor: attachment
            })
          )
    }

    state =
      state
      |> bind_capability(capability, @agent)
      |> Map.put(:speech_to_speech_ready?, true)

    held = SpeechToSpeech.hold(state)

    assert_receive {:sts_source_control_request, ^peer, :hold,
                    %{attachment: ^attachment, token: token, deadline_ms: deadline}}

    assert is_reference(token)
    assert deadline > System.monotonic_time(:millisecond)
    assert :sys.get_state(capability).held?
    assert %{token: ^token, phase: :holding} = held.source_cutover

    receipt = %{
      attachment: attachment,
      token: token,
      receiver: self(),
      old_epoch: make_ref(),
      held_epoch: make_ref()
    }

    assert :ok = Vxpipe.CallEngine.TestSTSSourceControlPeer.complete(peer, :hold, {:ok, receipt})
    assert_receive {hold_tag, {:ok, ^receipt}}

    assert {:reply, {:ok, ^receipt}} =
             :gen_server.check_response(
               {hold_tag, {:ok, receipt}},
               held.source_cutover.request_id
             )

    assert {:noreply, held_after} =
             Vxpipe.CallEngine.RoomAuthority.handle_info(
               {hold_tag, {:ok, receipt}},
               held
             )

    assert %{phase: :held, receipt: ^receipt} = held_after.source_cutover
    released = SpeechToSpeech.release(held_after)

    assert_receive {:sts_source_control_request, ^peer, :arm,
                    %{
                      attachment: ^attachment,
                      token: ^token,
                      receipt: ^receipt,
                      active_epoch: active_epoch,
                      deadline_ms: arm_deadline
                    }}

    assert is_reference(active_epoch)
    assert arm_deadline > System.monotonic_time(:millisecond)

    transfer_held = SpeechToSpeech.hold(released, :transfer)

    assert :ok =
             Vxpipe.CallEngine.TestSTSSourceControlPeer.complete(
               peer,
               :arm,
               {:ok, active_epoch}
             )

    assert_receive {arm_tag, {:ok, ^active_epoch}}

    assert {:noreply, after_arm} =
             Vxpipe.CallEngine.RoomAuthority.handle_info(
               {arm_tag, {:ok, active_epoch}},
               transfer_held
             )

    assert %{phase: :holding, token: next_token} = after_arm.source_cutover
    refute next_token == token
    assert :sys.get_state(capability).held?

    assert_receive {:sts_source_control_request, ^peer, :hold,
                    %{
                      attachment: ^attachment,
                      token: ^next_token,
                      deadline_ms: next_deadline
                    }}

    assert next_deadline > System.monotonic_time(:millisecond)

    next_receipt = %{
      attachment: attachment,
      token: next_token,
      receiver: self(),
      old_epoch: active_epoch,
      held_epoch: make_ref()
    }

    assert :ok =
             Vxpipe.CallEngine.TestSTSSourceControlPeer.complete(
               peer,
               :hold,
               {:ok, next_receipt}
             )

    assert_receive {next_hold_tag, {:ok, ^next_receipt}}

    assert {:noreply, held_again} =
             Vxpipe.CallEngine.RoomAuthority.handle_info(
               {next_hold_tag, {:ok, next_receipt}},
               after_arm
             )

    reopened = SpeechToSpeech.release(held_again)

    assert_receive {:sts_source_control_request, ^peer, :arm,
                    %{
                      attachment: ^attachment,
                      token: ^next_token,
                      receipt: ^next_receipt,
                      active_epoch: final_epoch
                    }}

    assert :ok =
             Vxpipe.CallEngine.TestSTSSourceControlPeer.complete(peer, :arm, {:ok, final_epoch})

    assert_receive {final_arm_tag, {:ok, ^final_epoch}}

    assert {:noreply, completed} =
             Vxpipe.CallEngine.RoomAuthority.handle_info(
               {final_arm_tag, {:ok, final_epoch}},
               reopened
             )

    assert completed.source_cutover == nil
    assert is_reference(completed.speech_to_speech_capability.input_epoch)
    assert :sys.get_state(capability).held? == false
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

  defp start_transfer_provider(kind) do
    alias Vxpipe.CallEngine.RoomCapabilitySupervisor
    alias Vxpipe.CallEngine.Speech.Session
    alias Vxpipe.CallEngine.TestAudioOutputSink
    alias Vxpipe.CallEngine.TestGPTLiveTransport
    alias Vxpipe.Providers.OpenAI.{GPTLive, GPTLiveSession}

    incarnation = "sts-transfer-#{System.unique_integer([:positive])}"
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: incarnation}, id: make_ref())
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: make_ref())

    {provider_spec, provider_private} =
      case kind do
        :morse ->
          {{Vxpipe.Providers.MorseCode.DuplexSTSSession, [clock: :manual]}, []}

        :gpt_live ->
          {:ok, config} = GPTLive.new(api_key: "synthetic", backend_model: "gpt-5.6")

          {{GPTLiveSession, [backend_model: "gpt-5.6"]},
           [config: config, wire_module: TestGPTLiveTransport, wire_options: [observer: self()]]}
      end

    assert {:ok, capability} =
             RoomCapabilitySupervisor.start_speech_to_speech(
               incarnation,
               owner: self(),
               agent_id: @agent,
               human_id: @human,
               provider: provider_spec,
               provider_private: provider_private,
               sink: sink,
               frame_identity: %{},
               caller_source: :sts,
               policy: %Vxpipe.CallEngine.MediaPolicy.Effective{
                 audio_routes: :unrestricted,
                 transcript_routes: :unrestricted,
                 record_audio: true,
                 save_transcripts: true
               }
             )

    wire =
      case kind do
        :morse ->
          nil

        :gpt_live ->
          assert_receive {:test_gpt_live_started, wire, _connection}, 5_000
          assert_receive {:test_gpt_live_control, ^wire, %{"type" => "session.start"}}

          TestGPTLiveTransport.deliver_sync(wire, %{
            "type" => "session.started",
            "session" => %{"id" => "s"}
          })

          wire
      end

    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
    provider = Session.provider(:sys.get_state(capability).session)
    {state(incarnation) |> bind_capability(capability, @agent), capability, provider, wire}
  end

  defp change_gpt_live_hold(state, wire, held?) do
    observer = self()

    start_supervised!(
      Supervisor.child_spec(
        {Task,
         fn ->
           result =
             if held?,
               do: SpeechToSpeech.hold(state),
               else: SpeechToSpeech.release(state)

           send(observer, {:transfer_hold_result, result})
         end},
        id: make_ref()
      )
    )

    command = if held?, do: "session.input_audio.mute", else: "session.input_audio.unmute"
    event = if held?, do: "session.input_audio.muted", else: "session.input_audio.unmuted"

    assert_receive {:test_gpt_live_control, ^wire, %{"type" => ^command, "event_id" => event_id}},
                   1_000

    Vxpipe.CallEngine.TestGPTLiveTransport.deliver_sync(wire, %{
      "type" => event,
      "client_event_id" => event_id
    })

    assert_receive {:transfer_hold_result, result}, 1_000
    result
  end

  defp transfer_context(state) do
    %Context{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      agent_participant_id: @agent,
      source_participant_id: @human,
      connection_id: @human_connection,
      command_id: "transfer-test",
      correlation_id: "transfer-test"
    }
  end

  defp state(incarnation \\ @incarnation) do
    recorder = %Recorder{port: nil, participant_activations: %{@agent => "activation-sts"}}

    snapshot = %RoomSnapshot{
      tenant_id: @tenant,
      room_id: @room,
      incarnation_id: incarnation,
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
        incarnation_id: incarnation,
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

  defp start_real_capability(options \\ []) do
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
             provider:
               if(Keyword.get(options, :duplex?, false),
                 do: {Vxpipe.Providers.MorseCode.DuplexSTSSession, [clock: :manual]},
                 else: {Vxpipe.Providers.MorseCode.STSSession, []}
               ),
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
