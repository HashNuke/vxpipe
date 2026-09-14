defmodule Vxpipe.CallEngine.HumanWebTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Archive.Fact

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallDefinition,
    CallInvocation,
    CallVariables,
    ConnectionAttachment,
    DefinitionCompiler,
    RoomMixer,
    TestAudioOutputSink,
    TestCollectingArchiveWriter,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport,
    TestSpeechToTextTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, ParticipantTransferControl, SendText}
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed}
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: PolicyAuthority

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestSelectiveAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [api_key: "runtime-test-secret"],
      transport: {TestSpeechToTextTransport, observer: self()},
      media_ingress: [
        maximum_frames: 50,
        maximum_bytes: 65_536,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 10
      ]
    ]

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-test-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {TestTextToSpeechTransport, observer: self()},
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:text_to_speech, text_to_speech)
      |> Keyword.put(:speech_to_text, speech_to_text)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  for failure <- [:kill, :unavailable] do
    @private_speech_failure failure
    @tag capture_log: true
    test "private speech stays closed and #{@private_speech_failure} fails only the transfer" do
      plan = compile_plan(support_stt: true)
      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      reception = Map.fetch!(plan.participants, "reception")
      assert {:ok, room} = CallEngine.start_call(plan)
      assert_receive {:test_tts_transport_started, _source_tts, _}, 2_000

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :private_caller)

      support_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :private_support)

      assert {:ok, _} = attach(plan, room, caller, "caller-connection", caller_sink)
      source = AgentActivationSupervisor.whereis_child(reception.activation_id, :session)
      begin_transfer(plan, room, caller, "private-speech-cancelled")
      assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

      assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt_id}} =
               attach(plan, room, support, "support-connection", support_sink)

      authority = room_authority(plan)
      pending = :sys.get_state(authority).pending_participant_transfer
      command = attachment_command(plan, room, support, "support-connection")

      assert {:ok, %{capability: capability, ingress: ingress} = binding} =
               Vxpipe.CallEngine.RoomAuthority.prepare_transfer_speech_to_text(
                 authority,
                 command,
                 attempt_id
               )

      assert {:ok, ^binding} =
               Vxpipe.CallEngine.RoomAuthority.prepare_transfer_speech_to_text(
                 authority,
                 command,
                 attempt_id
               )

      assert {:error, %Vxpipe.CallEngine.Error{code: :speech_to_text_not_bindable}} =
               CallEngine.activate_speech_to_text(command)

      capability_monitor = Process.monitor(capability)
      ingress_monitor = Process.monitor(ingress)
      speech = :sys.get_state(capability)
      assert speech.private_allocation.owner == pending.task.pid
      assert speech.private_allocation.attempt_id == attempt_id
      assert speech.private_allocation.deadline_ms == pending.deadline_ms
      assert speech.transport == nil
      assert :sys.get_state(ingress).opening_input_admission == :closed

      _ =
        Vxpipe.CallEngine.RoomAuthority.ConnectionLifecycle.open_inputs(:sys.get_state(authority))

      assert :sys.get_state(ingress).opening_input_admission == :closed
      refute MapSet.member?(speech.policy.present_participant_ids, support.participant_id)
      refute_receive {:test_stt_transport_started, _, _}

      assert :ok =
               CallEngine.participant_transfer_control(
                 transfer_control(plan, room, support, attempt_id, :accept)
               )

      assert :ok =
               CallEngine.participant_transfer_control(
                 transfer_control(plan, room, support, attempt_id, :media_ready)
               )

      finish_private_briefing(briefing_tts, support_sink)
      refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "private-speech-cancelled"}}
      assert {:ok, _scope} = Phase.scope(pending.task.pid)
      assert :sys.get_state(ingress).opening_input_admission == :closed

      policy_authority = PolicyAuthority.whereis(room.incarnation_id)

      present =
        speech.policy.present_participant_ids
        |> MapSet.delete(reception.participant_id)
        |> MapSet.put(support.participant_id)

      assert {:ok, candidate} = PolicyAuthority.preview_presence(policy_authority, present)

      assert {:ok, _prepared} =
               SpeechToText.prepare_policy(capability, candidate,
                 owner: pending.task.pid,
                 attempt_id: attempt_id,
                 deadline_ms: pending.deadline_ms
               )

      assert_receive {:test_stt_transport_started, transport, _}, 2_000
      transport_monitor = Process.monitor(transport)
      assert PolicyAuthority.snapshot(policy_authority) == speech.policy
      assert :sys.get_state(ingress).opening_input_admission == :closed

      case @private_speech_failure do
        :kill -> Process.exit(capability, :kill)
        :unavailable -> SpeechToText.fail(capability, :media_overloaded)
      end

      assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _reason}, 2_000
      assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, _reason}, 2_000
      assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _reason}, 2_000

      assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "private-speech-cancelled"}},
                     2_000

      assert_receive {:vxpipe_connection_unavailable, :transfer_failed}, 2_000
      assert AgentActivationSupervisor.whereis_child(reception.activation_id, :session) == source
      assert :sys.get_state(authority).pending_participant_transfer == nil

      assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
               Vxpipe.CallEngine.RoomAuthority.prepare_transfer_speech_to_text(
                 authority,
                 command,
                 attempt_id
               )
    end
  end

  test "private speech allocation respects an unconfigured destination" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _}, 2_000
    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :no_stt_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :no_stt_support)
    assert {:ok, _} = attach(plan, room, caller, "caller-connection", caller_sink)
    begin_transfer(plan, room, caller, "no-private-stt")
    assert_receive {:test_tts_transport_started, _briefing_tts, _}, 2_000

    assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt_id}} =
             attach(plan, room, support, "support-connection", support_sink)

    authority = room_authority(plan)
    command = attachment_command(plan, room, support, "support-connection")

    assert {:ok, nil} =
             Vxpipe.CallEngine.RoomAuthority.prepare_transfer_speech_to_text(
               authority,
               command,
               attempt_id
             )

    refute_receive {:test_stt_transport_started, _, _}

    assert Map.fetch!(:sys.get_state(authority).connections, command.connection_id).speech_to_text ==
             nil
  end

  test "private speech allocation rejects foreign connections, identities and attempts" do
    plan = compile_plan(support_stt: true)
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _}, 2_000
    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :auth_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :auth_support)
    assert {:ok, _} = attach(plan, room, caller, "caller-connection", caller_sink)
    begin_transfer(plan, room, caller, "private-speech-authorization")
    assert_receive {:test_tts_transport_started, _briefing_tts, _}, 2_000

    assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt_id}} =
             attach(plan, room, support, "support-connection", support_sink)

    authority = room_authority(plan)
    command = attachment_command(plan, room, support, "support-connection")

    for {candidate, attempt} <- [
          {%{command | actor_id: "foreign-actor"}, attempt_id},
          {%{command | tenant_id: "foreign-tenant"}, attempt_id},
          {%{command | room_id: "foreign-room"}, attempt_id},
          {%{command | incarnation_id: "foreign-incarnation"}, attempt_id},
          {%{command | participant_id: caller.participant_id}, attempt_id},
          {%{command | connection_id: "caller-connection"}, attempt_id},
          {%{command | deadline: DateTime.add(DateTime.utc_now(), -1, :second)}, attempt_id},
          {command, "foreign-attempt"}
        ] do
      assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
               Vxpipe.CallEngine.RoomAuthority.prepare_transfer_speech_to_text(
                 authority,
                 candidate,
                 attempt
               )
    end

    foreign = start_supervised!({Agent, fn -> nil end})

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             Agent.get(foreign, fn _ ->
               Vxpipe.CallEngine.RoomAuthority.prepare_transfer_speech_to_text(
                 authority,
                 command,
                 attempt_id
               )
             end)

    state = :sys.get_state(authority)
    assert Map.fetch!(state.connections, command.connection_id).speech_to_text == nil
    refute_receive {:test_stt_transport_started, _, _}
  end

  test "the prepared phase retains its scope and owner loss discards the private destination" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    reception = Map.fetch!(plan.participants, "reception")
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _}, 2_000
    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :phase_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :phase_support)
    assert {:ok, _} = attach(plan, room, caller, "caller-connection", caller_sink)
    source = AgentActivationSupervisor.whereis_child(reception.activation_id, :session)

    begin_transfer(plan, room, caller, "phase-owner-lost")
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000
    briefing_monitor = Process.monitor(briefing_tts)

    assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt_id}} =
             attach(plan, room, support, "support-connection", support_sink)

    assert {:ok, %ConnectionAttachment{transfer_attempt_id: ^attempt_id}} =
             attach(plan, room, support, "second-support-connection", support_sink)

    authority = room_authority(plan)
    pending = :sys.get_state(authority).pending_participant_transfer
    phase = pending.task.pid
    phase_monitor = Process.monitor(phase)

    assert {:ok, scope} = Phase.scope(phase)
    assert scope.owner == phase
    assert scope.authority == authority
    assert scope.attempt_id == attempt_id
    assert scope.incarnation_id == room.incarnation_id
    assert scope.deadline_ms == pending.deadline_ms
    assert {:error, :not_owner} = Phase.complete(phase, pending.deadline_ms)
    assert {:ok, ^scope} = Phase.scope(phase)

    Process.exit(phase, :kill)
    assert_receive {:DOWN, ^phase_monitor, :process, ^phase, :killed}, 2_000
    assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "phase-owner-lost"}}, 2_000
    assert_receive {:vxpipe_connection_unavailable, :transfer_failed}, 2_000
    assert_receive {:vxpipe_connection_unavailable, :transfer_failed}, 2_000
    assert_receive {:DOWN, ^briefing_monitor, :process, ^briefing_tts, _reason}, 2_000
    assert AgentActivationSupervisor.whereis_child(reception.activation_id, :session) == source
    state = :sys.get_state(authority)
    assert state.pending_participant_transfer == nil
    assert Map.keys(state.connections) == ["caller-connection"]
    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _}
    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "phase-owner-lost"}}
  end

  test "activates a destination's configured STT only after acceptance and reuses it" do
    plan = compile_plan(support_stt: true)
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _}, 2_000
    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :stt_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :stt_support_sink)

    assert {:ok, _} = attach(plan, room, caller, "caller-connection", caller_sink)
    begin_transfer(plan, room, caller, "transcribed-transfer")
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

    assert {:ok, %ConnectionAttachment{media_ingress: nil, transfer_attempt_id: attempt_id}} =
             attach(plan, room, support, "support-connection", support_sink)

    command = attachment_command(plan, room, support, "support-connection")

    assert {:error, %Vxpipe.CallEngine.Error{code: :speech_to_text_not_bindable}} =
             CallEngine.activate_speech_to_text(command)

    refute_receive {:test_stt_transport_started, _, _}

    pending = :sys.get_state(room_authority(plan)).pending_participant_transfer
    phase = pending.task.pid
    phase_monitor = Process.monitor(phase)
    assert {:ok, scope} = Phase.scope(phase)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    assert {:ok, ^scope} = Phase.scope(phase)
    finish_private_briefing(briefing_tts, support_sink)

    assert_receive {:vxpipe_transfer_main_media, ^attempt_id,
                    %ConnectionAttachment{admission: :main}},
                   2_000

    assert_receive {:DOWN, ^phase_monitor, :process, ^phase, :normal}, 2_000

    command = attachment_command(plan, room, support, "support-connection")
    assert {:ok, ingress} = CallEngine.activate_speech_to_text(command)
    assert is_pid(ingress)
    assert_receive {:test_stt_transport_started, _transport, _}, 2_000
    assert {:ok, ^ingress} = CallEngine.activate_speech_to_text(command)
    refute_receive {:test_stt_transport_started, _, _}

    assert {:error, %Vxpipe.CallEngine.Error{code: :connection_not_attached}} =
             CallEngine.activate_speech_to_text(%{command | actor_id: "wrong-actor"})

    foreign = start_supervised!({Agent, fn -> :ready end})

    assert {:error, %Vxpipe.CallEngine.Error{code: :connection_not_attached}} =
             Agent.get(foreign, fn _ -> CallEngine.activate_speech_to_text(command) end)
  end

  test "an exact web destination hears its private briefing before promotion" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan, archive: archive_options())
    variables = CallVariables.whereis(room.incarnation_id)
    lifecycle = call_lifecycle(room.incarnation_id)

    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :caller_output_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :support_output_sink)

    assert {:ok,
            %ConnectionAttachment{
              admission: :main,
              room_audio_input_mode: :enabled,
              room_audio_output_mode: :mix_minus
            }} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    source_supervisor = participant_supervisor(plan, reception.participant_id)
    source_monitor = Process.monitor(source_supervisor)

    assert :ok =
             CallEngine.send_text(
               send_command(plan, room, caller, "Please connect me to human support.")
             )

    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    reason = "Taylor is calling about order 17."

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "human-support-transfer",
               name: "transfer",
               arguments: %{"destination" => "human-support", "reason" => reason}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, support.participant_id)

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              room_audio_input_mode: :disabled,
              room_audio_output_mode: :disabled,
              transfer_attempt_id: attempt_id
            } = pending_attachment} =
             attach(plan, room, support, "support-connection", support_sink)

    assert is_binary(attempt_id)
    assert :disabled = CallEngine.room_audio_configuration(pending_attachment)
    assert :disabled = CallEngine.room_audio_output_configuration(pending_attachment)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "human-support-transfer"}},
                   50

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    assert_receive {:test_tts_control, ^briefing_tts, speak}, 2_000

    assert JSON.decode!(speak) == %{
             "text" => reason <> " This call is recorded.",
             "type" => "Speak"
           }

    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(briefing_tts, <<1, 0, 2, 0>>)

    assert_receive {:test_audio_output, ^support_sink, _frame}, 2_000
    refute_receive {:test_audio_output, ^caller_sink, _frame}, 50

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )

    assert_receive {:test_audio_output_finish, ^support_sink, _turn}, 2_000

    usage_facts = collect_tts_usage(2)

    assert Enum.all?(usage_facts, fn fact ->
             fact.call_id == plan.call_id and
               fact.participant_id == support.participant_id and
               fact.activation_id == nil and
               fact.payload["provider"]["name"] == "deepgram" and
               fact.payload["provider"]["integration_id"] == "test-voice" and
               fact.payload["provider"]["request_id"] == "req" and
               fact.payload["provider"]["operation_id"] == "private-briefing"
           end)

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "human-support-transfer"}},
                   50

    assert :ok = TestAudioOutputSink.playback_started(support_sink)
    assert :ok = TestAudioOutputSink.playback_completed(support_sink)

    assert_receive {:vxpipe_transfer_main_media, ^attempt_id,
                    %ConnectionAttachment{
                      admission: :main,
                      room_audio_input_mode: :enabled,
                      room_audio_output_mode: :mix_minus
                    }},
                   2_000

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "human-support-transfer",
                      result: %{
                        "destination" => "human-support",
                        "status" => "completed"
                      }
                    }},
                   2_000

    assert_receive {:DOWN, ^source_monitor, :process, ^source_supervisor, _reason}, 2_000

    assert {:ok, support_snapshot} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, support.participant_id)

    assert support_snapshot.participant_id == support.participant_id
    assert CallVariables.whereis(room.incarnation_id) == variables
    assert call_lifecycle(room.incarnation_id) == lifecycle
    assert AgentActivationSupervisor.whereis_child(reception.activation_id, :session) == nil
  end

  test "only the exact destination connection can control the current attempt" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :control_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :control_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "controlled-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    stale =
      transfer_control(plan, room, support, "xfer_stale_attempt", :accept)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(stale)

    forged_actor =
      transfer_control(plan, room, support, attempt_id, :accept, actor_id: "another-actor")

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(forged_actor)

    exact = transfer_control(plan, room, support, attempt_id, :accept)

    foreign_connection =
      start_supervised!({Agent, fn -> :ready end}, id: :foreign_transfer_connection)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             Agent.get(foreign_connection, fn :ready ->
               CallEngine.participant_transfer_control(exact)
             end)

    assert :ok = CallEngine.participant_transfer_control(exact)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(exact)

    ready = transfer_control(plan, room, support, attempt_id, :media_ready)
    assert :ok = CallEngine.participant_transfer_control(ready)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(ready)
  end

  test "a dropped private destination fails only that attempt" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :drop_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :drop_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "dropped-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    support_connection =
      start_supervised!({Agent, fn -> :ready end}, id: :dropping_transfer_connection)

    command = attachment_command(plan, room, support, "support-connection")

    assert {:ok, %ConnectionAttachment{admission: :transfer_preparation}} =
             Agent.get(support_connection, fn :ready ->
               CallEngine.attach_connection(command, support_sink)
             end)

    assert :ok = stop_supervised(:dropping_transfer_connection)

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "dropped-human-transfer",
                      name: "transfer",
                      reason: :tool_failed
                    }},
                   2_000

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "dropped-human-transfer"}},
                   50

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               support.participant_id
             )
  end

  test "a timed-out destination cannot use late readiness to join main media" do
    plan = compile_plan(transfer_timeout_ms: 1_000)
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :timeout_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :timeout_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "timed-out-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    authority = room_authority(plan)
    pending = :sys.get_state(authority).pending_participant_transfer
    phase = pending.task.pid
    phase_monitor = Process.monitor(phase)
    assert {:ok, scope} = Phase.scope(phase)
    assert scope.deadline_ms == pending.deadline_ms
    assert :ok = :sys.suspend(authority)

    on_exit(fn ->
      try do
        :sys.resume(authority)
      catch
        :exit, _reason -> :ok
      end
    end)

    assert_receive {:DOWN, ^phase_monitor, :process, ^phase, :normal}, 2_000
    assert :ok = :sys.resume(authority)

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{
                      tool_call_id: "timed-out-human-transfer",
                      reason: :tool_failed
                    }},
                   2_000

    assert_receive {:vxpipe_connection_unavailable, :transfer_failed}, 2_000

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_rejected}} =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _attachment}, 50

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "timed-out-human-transfer"}},
                   50

    assert is_pid(AgentActivationSupervisor.whereis_child(reception.activation_id, :session))

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               support.participant_id
             )
  end

  @tag capture_log: true
  test "phase loss during policy adoption cannot publish a successful transfer" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _}, 2_000
    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :commit_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :commit_support)

    assert {:ok, caller_attachment} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    enforcer =
      start_supervised!({Vxpipe.CallEngine.TestMediaPolicyEnforcer, owner: self(), mode: :ok})

    assert {:ok, _} = CallEngine.register_room_audio_enforcer(caller_attachment, enforcer)
    assert_receive {:media_policy_applied, ^enforcer, _}

    begin_transfer(plan, room, caller, "phase-lost-during-commit")
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

    assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt_id}} =
             attach(plan, room, support, "support-connection", support_sink)

    authority = room_authority(plan)
    authority_monitor = Process.monitor(authority)
    phase = :sys.get_state(authority).pending_participant_transfer.task.pid
    phase_monitor = Process.monitor(phase)
    assert {:ok, _} = Phase.scope(phase)

    :sys.replace_state(enforcer, &%{&1 | mode: :manual})

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    finish_private_briefing(briefing_tts, support_sink)
    assert_receive {:media_policy_applied, ^enforcer, _}, 2_000
    Process.exit(phase, :kill)
    assert_receive {:DOWN, ^phase_monitor, :process, ^phase, :killed}, 2_000
    Vxpipe.CallEngine.TestMediaPolicyEnforcer.acknowledge(enforcer, :ok)

    assert_receive {:DOWN, ^authority_monitor, :process, ^authority, :shutdown}, 2_000
    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "phase-lost-during-commit"}}
    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _}
  end

  @tag capture_log: true
  test "a failed privacy barrier closes the room before bridge or source handoff" do
    plan =
      compile_plan(
        support_while_present: %{
          audio_routes: %{
            "caller" => ["human-support"],
            "human-support" => ["caller"]
          },
          transcript_routes: %{},
          record_audio: false,
          save_transcripts: false
        }
      )

    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    room_monitor = Process.monitor(room_authority)

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :policy_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :policy_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "policy-failed-human-transfer")
    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    force_future_mixer_revision(room.incarnation_id)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    finish_private_briefing(briefing_tts, support_sink)

    assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :shutdown}, 2_000
    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _attachment}, 50

    refute_receive {:vxpipe_event,
                    %ToolCallCompleted{tool_call_id: "policy-failed-human-transfer"}},
                   50
  end

  defp compile_plan(options \\ []) do
    transfer_timeout_ms = Keyword.get(options, :transfer_timeout_ms, 30_000)

    support = %{
      type: "human",
      description: "A human support specialist",
      connection: %{
        service: "web",
        mode: "receive",
        admission: "transfer"
      },
      transfer_notice: "This call is recorded."
    }

    support =
      if Keyword.get(options, :support_stt, false),
        do: Map.put(support, :capabilities, %{speech_to_text: "test-stt"}),
        else: support

    support =
      case Keyword.get(options, :support_while_present) do
        nil -> support
        policy -> Map.put(support, :while_present, policy)
      end

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 transfer_policy: %{attempt_timeout_ms: transfer_timeout_ms},
                 participants: %{
                   "caller" => %{
                     type: "human",
                     connection: %{
                       service: "web",
                       mode: "receive",
                       admission: "start_call"
                     }
                   },
                   "reception" => %{
                     type: "agent",
                     prompt: "Route callers safely.",
                     capabilities: %{
                       model_inference: "test-model",
                       text_to_speech: "test-voice"
                     },
                     tools: %{},
                     transfers: ["human-support"]
                   },
                   "human-support" => support
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "human-transfer-definition",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "human-transfer-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-human-transfer",
               actor_id: "actor-human-transfer",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{
                 "test-model" => %{
                   kind: :model_inference,
                   provider: :req_llm,
                   options: %{model: "test:scripted"}
                 },
                 "test-stt" => %{
                   kind: :speech_to_text,
                   provider: Flux,
                   options: %{model: "flux-general-en", encoding: :opus, sample_rate: 48_000}
                 },
                 "test-voice" => %{
                   kind: :text_to_speech,
                   provider: FluxTextToSpeech,
                   options: %{
                     model: "flux-test-voice",
                     encoding: :linear16,
                     sample_rate: 48_000
                   }
                 }
               },
               host_tools: %{}
             })

    plan
  end

  defp attach(plan, room, participant, connection_id, output_sink) do
    command = attachment_command(plan, room, participant, connection_id)
    CallEngine.attach_connection(command, output_sink)
  end

  defp attachment_command(plan, room, participant, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    command
  end

  defp send_command(plan, room, caller, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "caller-connection",
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    command
  end

  defp begin_transfer(plan, room, caller, tool_call_id) do
    assert :ok =
             CallEngine.send_text(
               send_command(plan, room, caller, "Please connect me to human support.")
             )

    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: tool_call_id,
               name: "transfer",
               arguments: %{
                 "destination" => "human-support",
                 "reason" => "Taylor is calling about order 17."
               }
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp transfer_control(plan, room, participant, attempt_id, action, overrides \\ []) do
    assert {:ok, command} =
             ParticipantTransferControl.new(
               Keyword.merge(
                 [
                   tenant_id: plan.tenant_id,
                   actor_id: plan.actor_id,
                   room_id: plan.room_id,
                   incarnation_id: room.incarnation_id,
                   participant_id: participant.participant_id,
                   connection_id: "support-connection",
                   attempt_id: attempt_id,
                   action: action,
                   deadline: future_deadline()
                 ],
                 overrides
               )
             )

    command
  end

  defp participant_supervisor(plan, participant_id) do
    assert [{supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:participant_supervisor, plan.tenant_id, plan.room_id, participant_id}
             )

    supervisor
  end

  defp call_lifecycle(incarnation_id) do
    assert [{lifecycle, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:call_lifecycle, incarnation_id}
             )

    lifecycle
  end

  defp room_authority(plan) do
    assert [{authority, _}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    authority
  end

  defp force_future_mixer_revision(incarnation_id) do
    incarnation_id
    |> RoomMixer.whereis()
    |> :sys.replace_state(fn state ->
      policy = %{state.policy | revision: state.policy.revision + 100}
      %{state | policy: policy}
    end)
  end

  defp finish_private_briefing(briefing_tts, support_sink) do
    assert_receive {:test_tts_control, ^briefing_tts, _speak}, 2_000
    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(briefing_tts, <<1, 0, 2, 0>>)

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )

    assert_receive {:test_audio_output, ^support_sink, _frame}, 2_000
    assert_receive {:test_audio_output_finish, ^support_sink, _turn}, 2_000
    assert :ok = TestAudioOutputSink.playback_started(support_sink)
    assert :ok = TestAudioOutputSink.playback_completed(support_sink)
  end

  defp archive_options do
    [
      enabled: true,
      writer: {TestCollectingArchiveWriter, self()},
      maximum_pending_facts: 64,
      retry_delay_ms: 5,
      drain_timeout_ms: 1_000
    ]
  end

  defp collect_tts_usage(count, facts \\ [])

  defp collect_tts_usage(0, facts), do: Enum.reverse(facts)

  defp collect_tts_usage(count, facts) do
    receive do
      {:test_archive_fact,
       %Fact{kind: :usage_observed, payload: %{"capability" => "text_to_speech"}} = fact} ->
        collect_tts_usage(count - 1, [fact | facts])

      {:test_archive_fact, %Fact{}} ->
        collect_tts_usage(count, facts)
    after
      2_000 -> flunk("timed out waiting for private briefing usage")
    end
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
