defmodule Vxpipe.CallEngine.HumanWebTransferRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Archive.Fact

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallSpec,
    CallInvocation,
    CallVariables,
    ConnectionAttachment,
    CallSpecCompiler,
    TestAudioOutputSink,
    TestTransferConnection,
    TestCollectingArchiveWriter,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport,
    TestSpeechToTextTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, ParticipantTransferControl, SendText}
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed}
  alias Vxpipe.Providers.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: PolicyAuthority

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    speech_to_text = [
      providers: %{
        Flux.Session => [
          enabled: true,
          wire_module: TestSpeechToTextTransport,
          wire_options: [observer: self(), ready_on_start: true],
          media_ingress: [
            maximum_frames: 50,
            maximum_bytes: 65_536,
            maximum_age_ms: 1_000,
            maximum_consecutive_overflows: 10
          ]
        ]
      }
    ]

    text_to_speech = [
      providers: %{
        FluxTextToSpeech.Session => [
          enabled: true,
          wire_module: TestTextToSpeechTransport,
          wire_options: [observer: self(), ready_on_start: true],
          maximum_requests: 2
        ]
      }
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

  for available? <- [true, false] do
    @briefing_credential_available available?
    test "private briefing rechecks its source credential when available=#{@briefing_credential_available}" do
      plan = compile_plan(speech_credential_name: "source-voice", wait_sounds: nil)
      binding = {plan.tenant_id, "deepgram", "source-voice"}

      store =
        start_supervised!(
          {Agent, fn -> %{binding => %{"api_key" => "source-private-marker"}} end}
        )

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan,
                 credential_source:
                   {Vxpipe.CallEngine.TestTenantCredentialSource, {:store, self(), store}}
               )

      assert_receive {:test_tts_transport_started, source_tts, source_connection}, 2_000
      assert source_connection.headers == [{"Authorization", "Token source-private-marker"}]
      assert_received {:tenant_credential_resolved, _, "deepgram", "source-voice"}

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller = Map.fetch!(plan.participants, "caller")
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", sink)

      if @briefing_credential_available do
        Agent.update(store, &Map.put(&1, binding, %{"api_key" => "current-private-marker"}))
      else
        Agent.update(store, &Map.delete(&1, binding))
      end

      submit_transfer(plan, room, caller, "credential-reader")
      tenant_id = plan.tenant_id
      assert_receive {:tenant_credential_resolved, ^tenant_id, "deepgram", "source-voice"}, 2_000

      if @briefing_credential_available do
        assert_receive {:test_tts_transport_started, _briefing, connection}, 2_000
        assert connection.headers == [{"Authorization", "Token current-private-marker"}]
      else
        assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "credential-reader"}}, 2_000
        refute_receive {:test_tts_transport_started, _, _}
        state = :sys.get_state(room_authority(plan))
        assert state.text_to_speech_capability != nil
        assert state.pending_participant_transfer == nil
      end
    end
  end

  for failure <- [:kill, :unavailable] do
    @private_speech_failure failure
    @tag capture_log: true
    test "private speech stays closed and #{@private_speech_failure} fails only the transfer" do
      plan = compile_plan(support_stt: true)
      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      reception = Map.fetch!(plan.participants, "reception")
      assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :private_caller)

      support_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :private_support)

      assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
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
      refute Map.has_key?(speech, :transport)
      assert :sys.get_state(ingress).opening_input_admission == :closed

      _ =
        Vxpipe.CallEngine.RoomAuthority.ConnectionLifecycle.open_inputs(:sys.get_state(authority))

      assert :sys.get_state(ingress).opening_input_admission == :closed
      refute MapSet.member?(speech.policy.present_participant_ids, support.participant_id)
      refute_receive {:test_stt_transport_started, _, _}

      assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
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

  test "private media without selected speech still requires prepared adoption" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :no_stt_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :no_stt_support)
    assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
    begin_transfer(plan, room, caller, "no-private-stt")
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

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

    assert {:ok, %{speech_to_text: nil} = media} =
             CallEngine.prepare_transfer_media(command, attempt_id)

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    finish_private_briefing(briefing_tts, support_sink)
    assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt_id}, 2_000

    assert :ok =
             CallEngine.participant_transfer_control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "no-private-stt"}}
    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _}
    assert {:ok, _scope} = Phase.scope(media.owner)
    assert PolicyAuthority.snapshot(PolicyAuthority.whereis(room.incarnation_id)) == media.policy
  end

  test "private speech allocation rejects foreign connections, identities and attempts" do
    plan = compile_plan(support_stt: true)
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :auth_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :auth_support)
    assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
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

  for refresh <- [:complete, :worker_loss] do
    @tag capture_log: true
    test "acceptance during audience refresh handles #{refresh}" do
      plan = compile_plan(transfer_timeout_ms: 10_000)
      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :refresh_caller)

      second_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :refresh_added)

      support_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :refresh_support)

      assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
      begin_transfer(plan, room, caller, "refresh-race")
      assert_receive {:test_tts_transport_started, briefing, _}, 2_000

      assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt}} =
               attach_ready(plan, room, support, "support-connection", support_sink)

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :media_ready)
               )

      finish_private_briefing(briefing, support_sink)
      assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt}, 2_000

      connection =
        TestTransferConnection.run(
          attachment_command(plan, room, caller, "caller-connection"),
          fn -> self() end
        )

      observer = self()
      token = make_ref()

      :ok =
        :sys.install(
          connection,
          {token,
           fn
             :done, _event, _process ->
               :done

             nil, {:in, {:"$gen_call", {worker, _}, :vxpipe_connection_readiness}}, _process ->
               send(observer, {:audience_readiness_paused, worker})

               receive do
                 {:resume_audience_readiness, ^token} -> :done
               after
                 2_000 -> :done
               end

             state, _event, _process ->
               state
           end, nil}
        )

      assert {:ok, _} =
               attach_ready(plan, room, caller, "additional-caller-connection", second_sink)

      assert_receive {:audience_readiness_paused, worker}, 1_000

      pending = :sys.get_state(room_authority(plan)).pending_participant_transfer

      assert {:ok, %{stage: :refresh_audience, worker: %Task{pid: ^worker}}} =
               Phase.scope(pending.task.pid)

      assert pending.deadline_ms - System.monotonic_time(:millisecond) > 5_000

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :accept)
               )

      if unquote(refresh) == :worker_loss do
        monitor = Process.monitor(worker)
        Process.exit(worker, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
      end

      send(connection, {:resume_audience_readiness, token})

      if unquote(refresh) == :complete do
        assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "refresh-race"}}, 2_000
        assert_receive {:vxpipe_transfer_active, ^attempt}, 1_000
        refute_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "refresh-race"}}, 0
      else
        assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "refresh-race"}}, 2_000
        refute_receive {:vxpipe_transfer_active, ^attempt}, 0
        refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "refresh-race"}}, 0
      end
    end
  end

  test "the prepared phase retains its scope and owner loss discards the private destination" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    reception = Map.fetch!(plan.participants, "reception")
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :phase_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :phase_support)
    assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
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

  for outcome <- [
        :drain,
        :drain_during_recheck,
        :deadline,
        :cue_loss,
        :readiness_loss,
        :policy_change,
        :unrelated_policy_change,
        :commit_policy_change,
        :commit_binding_change,
        :adopt_policy_change,
        :adopt_unrelated_change,
        :adopt_speech_change
      ] do
    @tag outcome: outcome
    test "human transfer keeps its cue barrier closed until #{outcome}", %{outcome: outcome} do
      plan =
        compile_plan(
          wait_sounds:
            if(
              outcome in [
                :policy_change,
                :commit_policy_change,
                :commit_binding_change,
                :adopt_policy_change
              ],
              do: %{},
              else: nil
            ),
          transfer_timeout_ms: 2_000,
          support_stt:
            outcome in [
              :readiness_loss,
              :policy_change,
              :unrelated_policy_change,
              :commit_policy_change,
              :commit_binding_change,
              :adopt_policy_change,
              :adopt_unrelated_change,
              :adopt_speech_change
            ],
          observer_policy:
            if outcome == :adopt_speech_change do
              %{save_transcripts: false}
            else
              if(
                outcome in [
                  :policy_change,
                  :commit_policy_change,
                  :commit_binding_change,
                  :adopt_policy_change
                ],
                do: %{transcript_routes: %{}, save_transcripts: false},
                else: %{}
              )
            end
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
      authority = room_authority(plan)
      room_monitor = Process.monitor(authority)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000
      source_monitor = Process.monitor(source_tts)

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self(), defer_drain: true},
          id: :cue_caller
        )

      support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :cue_support)
      assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)

      observer =
        if outcome in [
             :policy_change,
             :unrelated_policy_change,
             :commit_policy_change,
             :commit_binding_change,
             :adopt_policy_change,
             :adopt_unrelated_change,
             :adopt_speech_change
           ],
           do: connect_policy_observer(plan, room)

      begin_transfer(plan, room, caller, "cue-transfer")
      assert_receive {:test_tts_transport_started, briefing, _}, 2_000

      assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt}} =
               attach_ready(plan, room, support, "support-connection", support_sink)

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :media_ready)
               )

      finish_private_briefing(briefing, support_sink)
      assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt}, 2_000
      policy = PolicyAuthority.snapshot(PolicyAuthority.whereis(room.incarnation_id))

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :accept)
               )

      speech_transport =
        if outcome in [
             :readiness_loss,
             :policy_change,
             :unrelated_policy_change,
             :commit_policy_change,
             :commit_binding_change,
             :adopt_policy_change,
             :adopt_unrelated_change,
             :adopt_speech_change
           ] do
          assert_receive {:test_stt_transport_started, transport, _}, 1_000

          TestSpeechToTextTransport.deliver(
            transport,
            ~s({"type":"Connected","request_id":"cue-ready","sequence_id":0})
          )

          transport
        end

      assert_receive {:test_audio_output_drain, ^caller_sink}, 1_000
      refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cue-transfer"}}, 50
      refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 50
      assert PolicyAuthority.snapshot(PolicyAuthority.whereis(room.incarnation_id)) == policy

      case outcome do
        outcome when outcome in [:drain, :drain_during_recheck] ->
          connection =
            TestTransferConnection.run(
              attachment_command(plan, room, caller, "caller-connection"),
              fn -> self() end
            )

          if outcome == :drain_during_recheck do
            assert :ok = GenServer.call(connection, :defer_readiness)
            assert_receive {:test_transfer_readiness_waiting, ^connection}, 1_000
          end

          {player, _reply} = :sys.get_state(caller_sink).pending_drain
          player_monitor = Process.monitor(player)
          assert :ok = GenServer.call(caller_sink, :complete_drain)
          assert_receive {:DOWN, ^player_monitor, :process, ^player, :normal}, 1_000

          if outcome == :drain_during_recheck do
            refute_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "cue-transfer"}}, 100
            assert :ok = GenServer.call(connection, :complete_readiness)
          end

          assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cue-transfer"}}, 1_000
          assert_receive {:vxpipe_transfer_active, ^attempt}, 1_000

        outcome
        when outcome in [
               :policy_change,
               :unrelated_policy_change,
               :commit_policy_change,
               :commit_binding_change,
               :adopt_policy_change,
               :adopt_unrelated_change,
               :adopt_speech_change
             ] ->
          assert {:ok, before_binding} = CallEngine.RoomAuthority.readiness_binding(authority)
          pending = :sys.get_state(authority).pending_participant_transfer
          assert {:ok, scope} = Phase.scope(pending.task.pid)
          transport_monitor = Process.monitor(speech_transport)
          {first_player, _reply} = :sys.get_state(caller_sink).pending_drain
          first_monitor = Process.monitor(first_player)
          {_callback, first_correlation} = :sys.get_state(caller_sink).callback

          if outcome in [:adopt_policy_change, :adopt_unrelated_change, :adopt_speech_change] do
            joining =
              TestTransferConnection.run(
                attachment_command(plan, room, support, "support-connection"),
                fn -> self() end
              )

            assert :ok = GenServer.call(joining, :defer_adoption)
            assert :ok = GenServer.call(caller_sink, :complete_drain)
            assert_receive {:test_transfer_adoption_waiting, ^joining}, 1_000
            committed = PolicyAuthority.snapshot(PolicyAuthority.whereis(room.incarnation_id))
            assert MapSet.member?(committed.present_participant_ids, support.participant_id)

            assert {:ok, _changed} =
                     PolicyAuthority.admit(PolicyAuthority.whereis(room.incarnation_id), observer)

            assert :ok = GenServer.call(joining, :complete_adoption)

            if outcome == :adopt_speech_change do
              assert_receive {:test_stt_transport_started, replacement, _}, 1_000
              assert replacement != speech_transport
              refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cue-transfer"}}, 50

              TestSpeechToTextTransport.deliver(
                replacement,
                ~s({"type":"Connected","request_id":"changed-speech-ready","sequence_id":0})
              )
            end
          else
            if outcome in [:commit_policy_change, :commit_binding_change] do
              pause = pause_handoff_result(scope.worker.pid)
              assert :ok = GenServer.call(caller_sink, :complete_drain)
              assert_receive {:handoff_result_ready, ^pause}, 1_000

              assert {:ok, _changed} =
                       PolicyAuthority.admit(
                         PolicyAuthority.whereis(room.incarnation_id),
                         observer
                       )

              if outcome == :commit_binding_change do
                connection =
                  TestTransferConnection.run(
                    attachment_command(plan, room, support, "support-connection"),
                    fn -> self() end
                  )

                assert {:ok, _receipt} =
                         GenServer.call(connection, {:vxpipe_prepare_transfer_media, attempt})
              end

              send(scope.worker.pid, {:continue_handoff, pause})
            else
              assert {:ok, _changed} =
                       PolicyAuthority.admit(
                         PolicyAuthority.whereis(room.incarnation_id),
                         observer
                       )

              assert :ok = GenServer.call(caller_sink, :complete_drain)
            end
          end

          assert_receive {:DOWN, ^first_monitor, :process, ^first_player, :normal}, 1_000
          assert_receive {:test_audio_output_drain, ^caller_sink}, 1_000
          {second_player, _reply} = :sys.get_state(caller_sink).pending_drain
          assert second_player != first_player
          assert {:ok, current_scope} = Phase.scope(pending.task.pid)
          assert current_scope.deadline_ms == scope.deadline_ms
          {_callback, second_correlation} = :sys.get_state(caller_sink).callback
          assert second_correlation != first_correlation
          refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cue-transfer"}}, 50
          refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 50
          assert :sys.get_state(caller_sink).output_generation > 0

          if outcome in [
               :policy_change,
               :commit_policy_change,
               :commit_binding_change,
               :adopt_policy_change,
               :adopt_speech_change
             ] do
            assert_receive {:DOWN, ^transport_monitor, :process, ^speech_transport, _}, 1_000
          else
            refute_receive {:DOWN, ^transport_monitor, :process, ^speech_transport, _}, 50
          end

          refute_receive {:test_stt_transport_started, _replacement, _}, 50
          assert :ok = GenServer.call(caller_sink, :complete_drain)
          assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cue-transfer"}}, 1_000
          assert_receive {:vxpipe_transfer_active, ^attempt}, 1_000
          assert {:ok, after_binding} = CallEngine.RoomAuthority.readiness_binding(authority)
          assert after_binding.room == before_binding.room

          for {id, original} <- before_binding.connections do
            assert Map.fetch!(after_binding.connections, id).pid == original.pid
          end

        :deadline ->
          assert_receive {:DOWN, ^room_monitor, :process, ^authority, :handoff_recovery_failed},
                         3_000

          refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cue-transfer"}}, 50

        outcome when outcome in [:cue_loss, :readiness_loss] ->
          {player, _reply} = :sys.get_state(caller_sink).pending_drain
          assert :ok = GenServer.call(caller_sink, {:defer_drain, false})
          Process.exit(if(outcome == :cue_loss, do: player, else: speech_transport), :kill)
          assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "cue-transfer"}}, 1_000
          refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 50
          assert :sys.get_state(authority).pending_participant_transfer == nil
          assert MapSet.size(:sys.get_state(authority).held_participant_ids) == 0
          assert PolicyAuthority.snapshot(PolicyAuthority.whereis(room.incarnation_id)) == policy
      end
    end
  end

  for invalidation <- [
        :policy,
        :connection_generation,
        :release_error,
        :completion_policy,
        :deadline,
        :phase_loss,
        :speech_loss,
        :speech_loss_policy_first,
        :policy_loss
      ] do
    @tag capture_log: true, invalidation: invalidation
    test "closes a partially released handoff after #{invalidation}", %{
      invalidation: invalidation
    } do
      plan =
        compile_plan(
          wait_sounds: nil,
          transfer_timeout_ms: 2_000,
          support_stt: invalidation in [:speech_loss, :speech_loss_policy_first]
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

      authority = room_authority(plan)
      monitor = Process.monitor(authority)
      assert_receive {:test_tts_transport_started, source, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :released_caller)

      support_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :released_support)

      assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)

      observer =
        if invalidation in [:policy, :completion_policy], do: connect_policy_observer(plan, room)

      begin_transfer(plan, room, caller, "partial-release-transfer")
      assert_receive {:test_tts_transport_started, briefing, _}, 2_000

      assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt}} =
               attach_ready(plan, room, support, "support-connection", support_sink)

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :media_ready)
               )

      finish_private_briefing(briefing, support_sink)
      assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt}, 2_000
      assert :ok = GenServer.call(caller_sink, {:defer_release, true})

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :accept)
               )

      speech_transport =
        if invalidation in [:speech_loss, :speech_loss_policy_first] do
          assert_receive {:test_stt_transport_started, transport, _}, 1_000

          TestSpeechToTextTransport.deliver(
            transport,
            ~s({"type":"Connected","request_id":"release-ready","sequence_id":0})
          )

          transport
        end

      assert_receive {:test_audio_output_released, ^caller_sink}, 1_000
      assert :sys.get_state(caller_sink).output_generation == 0

      refute_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "partial-release-transfer"}},
                     50

      result =
        case invalidation do
          :policy ->
            assert {:ok, _changed} =
                     PolicyAuthority.admit(
                       PolicyAuthority.whereis(room.incarnation_id),
                       observer
                     )

            :ok

          :connection_generation ->
            connection =
              TestTransferConnection.run(
                attachment_command(plan, room, caller, "caller-connection"),
                fn -> self() end
              )

            assert :ok = GenServer.call(connection, :renew_readiness)
            :ok

          :completion_policy ->
            pending = :sys.get_state(authority).pending_participant_transfer
            assert {:ok, phase} = Phase.scope(pending.task.pid)
            token = pause_handoff_result(phase.worker.pid, :release)
            assert :ok = GenServer.call(caller_sink, {:complete_release, :ok})
            assert_receive {:handoff_result_ready, ^token}, 1_000

            assert {:ok, _changed} =
                     PolicyAuthority.admit(PolicyAuthority.whereis(room.incarnation_id), observer)

            send(phase.worker.pid, {:continue_handoff, token})
            :acknowledged

          :release_error ->
            {:error, :output_unavailable}

          :deadline ->
            pending = :sys.get_state(authority).pending_participant_transfer
            send(authority, {:vxpipe_participant_transfer_deadline, pending.task.ref})
            :cancelled

          :phase_loss ->
            pending = :sys.get_state(authority).pending_participant_transfer
            Process.exit(pending.task.pid, :kill)
            :cancelled

          :policy_loss ->
            Process.exit(PolicyAuthority.whereis(room.incarnation_id), :kill)
            :cancelled

          :speech_loss ->
            TestSpeechToTextTransport.disconnect(speech_transport, :test_release_failure)
            :cancelled

          :speech_loss_policy_first ->
            policy = PolicyAuthority.whereis(room.incarnation_id)
            policy_monitor = Process.monitor(policy)
            assert :ok = :sys.suspend(authority)

            try do
              TestSpeechToTextTransport.disconnect(speech_transport, :test_release_failure)

              assert_receive {:DOWN, ^policy_monitor, :process, ^policy,
                              {:media_policy_enforcer_unavailable, _enforcer, _reason}},
                             1_000
            after
              try do
                :sys.resume(authority)
              catch
                :exit, _already_stopped -> :ok
              end
            end

            :cancelled
        end

      if result not in [:acknowledged, :cancelled],
        do: assert(:ok == GenServer.call(caller_sink, {:complete_release, result}))

      refute_receive {:vxpipe_transfer_progress, ^attempt, %{phase: :recovering}}, 100
      assert_receive {:vxpipe_transfer_progress, ^attempt, %{phase: :failed}}, 1_000
      assert_receive {:DOWN, ^monitor, :process, ^authority, reason}, 1_000

      # Either the speech failure or the policy monitor can reach RoomAuthority first.
      if invalidation in [:speech_loss, :speech_loss_policy_first, :policy_loss],
        do: assert(reason in [:handoff_release_failed, :shutdown]),
        else: assert(reason == :handoff_release_failed)

      cause =
        case invalidation do
          :deadline ->
            "deadline_elapsed"

          :phase_loss ->
            "preparation_process_down"

          :policy_loss ->
            "source_authority_changed"

          speech_loss when speech_loss in [:speech_loss, :speech_loss_policy_first] ->
            "destination_speech_to_text_unavailable"

          _other ->
            "destination_media_unavailable"
        end

      assert_receive {:test_archive_fact,
                      %Fact{
                        kind: :participant_transfer_failed,
                        tool_call_id: "partial-release-transfer",
                        payload: %{"cause" => ^cause, "restoration" => "failed"}
                      }},
                     1_000

      refute_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "partial-release-transfer"}},
                     50

      refute_receive {:vxpipe_transfer_active, ^attempt}, 50
      refute_receive {:test_tts_transport_started, _recovery_or_redial, _}, 50
    end
  end

  @tag capture_log: true
  test "recovery cancellation wins over an already queued successful release" do
    plan = compile_plan(wait_sounds: nil)
    caller = Map.fetch!(plan.participants, "caller")
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    authority = room_authority(plan)
    observe_transfer_workers(authority)
    authority_monitor = Process.monitor(authority)
    assert_receive {:test_tts_transport_started, source, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source,
      ~s({"type":"Connected","request_id":"retained-source"})
    )

    sink = start_supervised!({TestAudioOutputSink, observer: self(), defer_drain: true})
    assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", sink)
    begin_transfer(plan, room, caller, "cancel-queued-recovery")
    assert_receive {:test_tts_transport_started, _briefing, _}, 2_000
    pending = :sys.get_state(authority).pending_participant_transfer
    Process.exit(pending.task.pid, :kill)

    assert_receive {:transfer_worker, %{count: 1}, %{outcome: :unexpected}}, 1_000

    assert_receive {:test_audio_output_drain, ^sink}, 1_000
    recovering = :sys.get_state(authority).pending_participant_transfer
    assert recovering.handoff.stage == :recovering
    assert {:ok, phase} = Phase.scope(recovering.task.pid)
    worker = phase.worker.pid
    worker_monitor = Process.monitor(worker)
    token = pause_handoff_result(worker, :recover)
    assert :ok = GenServer.call(sink, :complete_drain)
    assert_receive {:handoff_result_ready, ^token}, 1_000

    assert :ok = :sys.suspend(authority)

    try do
      # Put the cancellation first, then the actual successful worker result in the
      # authority mailbox. No wall-clock delay or fabricated readiness result is needed.
      send(authority, {:vxpipe_participant_transfer_deadline, recovering.task.ref})
      send(worker, {:continue_handoff, token})
      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 1_000
      assert {:ok, settled} = Phase.scope(recovering.task.pid)
      refute Map.has_key?(settled, :worker)
    after
      :sys.resume(authority)
    end

    attempt = recovering.attempt_id
    refute_receive {:vxpipe_transfer_progress, ^attempt, %{phase: :recovered}}, 100

    assert_receive {:DOWN, ^authority_monitor, :process, ^authority, :handoff_recovery_failed},
                   1_000

    assert_receive {:transfer_worker, %{count: 1}, %{outcome: :cancelled}}, 1_000
    refute_receive {:transfer_worker, _, _}, 0

    refute_receive {:test_tts_transport_started, _replacement, _}, 50
    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "cancel-queued-recovery"}}, 50
  end

  for change <- [:removes_speech, :unrelated] do
    @tag capture_log: true
    test "reconciles #{change} policy change during initial handoff preparation" do
      plan =
        compile_plan(
          support_stt: true,
          transfer_timeout_ms: 2_000,
          observer_policy:
            if(unquote(change) == :removes_speech,
              do: %{transcript_routes: %{}, save_transcripts: false},
              else: %{}
            )
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
      authority = room_authority(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000
      source_monitor = Process.monitor(source_tts)

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self(), defer_drain: true},
          id: :preparing_caller
        )

      support_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :preparing_support)

      assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
      observer = connect_policy_observer(plan, room)

      caller_connection =
        TestTransferConnection.run(
          attachment_command(plan, room, caller, "caller-connection"),
          fn -> self() end
        )

      assert :ok = GenServer.call(caller_connection, :defer_readiness)
      begin_transfer(plan, room, caller, "initial-preparation-transfer")
      assert_receive {:test_tts_transport_started, briefing, _}, 2_000

      assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt}} =
               attach_ready(plan, room, support, "support-connection", support_sink)

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :media_ready)
               )

      finish_private_briefing(briefing, support_sink)
      assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt}, 2_000

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt, :accept)
               )

      assert_receive {:test_stt_transport_started, speech_transport, _}, 1_000
      speech_monitor = Process.monitor(speech_transport)

      TestSpeechToTextTransport.deliver(
        speech_transport,
        ~s({"type":"Connected","request_id":"initial-ready","sequence_id":0})
      )

      assert_receive {:test_transfer_readiness_waiting, ^caller_connection}, 1_000
      pending = :sys.get_state(authority).pending_participant_transfer
      assert {:ok, scope} = Phase.scope(pending.task.pid)
      assert {:ok, before} = CallEngine.RoomAuthority.readiness_binding(authority)

      assert {:ok, _policy} =
               PolicyAuthority.admit(PolicyAuthority.whereis(room.incarnation_id), observer)

      assert :ok = GenServer.call(caller_connection, :complete_readiness)

      refute_receive {:vxpipe_event,
                      %ToolCallFailed{tool_call_id: "initial-preparation-transfer"}},
                     100

      assert_receive {:test_audio_output_drain, ^caller_sink}, 1_000
      assert {:ok, current_scope} = Phase.scope(pending.task.pid)
      assert current_scope.deadline_ms == scope.deadline_ms
      assert current_scope.worker.pid == scope.worker.pid
      assert current_scope.audience == scope.audience
      assert {:ok, after_preparation} = CallEngine.RoomAuthority.readiness_binding(authority)
      assert after_preparation.room == before.room
      assert after_preparation.participants == before.participants

      if unquote(change) == :removes_speech do
        assert_receive {:DOWN, ^speech_monitor, :process, ^speech_transport, _}, 1_000
      else
        refute_receive {:DOWN, ^speech_monitor, :process, ^speech_transport, _}, 50
      end

      refute_receive {:test_stt_transport_started, _replacement, _}, 50
      refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 50
      assert :ok = GenServer.call(caller_sink, :complete_drain)

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "initial-preparation-transfer"}},
                     1_000

      assert_receive {:vxpipe_transfer_active, ^attempt}, 1_000
    end
  end

  test "activates a destination's configured STT only after acceptance and reuses it" do
    plan = compile_plan(support_stt: true)
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :stt_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :stt_support_sink)

    assert {:ok, _} = attach_ready(plan, room, caller, "caller-connection", caller_sink)
    begin_transfer(plan, room, caller, "transcribed-transfer")
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

    assert {:ok, %ConnectionAttachment{media_ingress: nil, transfer_attempt_id: attempt_id}} =
             attach_ready(plan, room, support, "support-connection", support_sink)

    command = attachment_command(plan, room, support, "support-connection")

    assert {:error, %Vxpipe.CallEngine.Error{code: :speech_to_text_not_bindable}} =
             TestTransferConnection.run(command, fn ->
               CallEngine.activate_speech_to_text(command)
             end)

    refute_receive {:test_stt_transport_started, _, _}

    pending = :sys.get_state(room_authority(plan)).pending_participant_transfer
    phase = pending.task.pid
    phase_monitor = Process.monitor(phase)
    assert {:ok, scope} = Phase.scope(phase)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
             TestTransferConnection.control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert :ok =
             TestTransferConnection.control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    assert {:ok, ^scope} = Phase.scope(phase)
    finish_private_briefing(briefing_tts, support_sink)
    assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt_id}, 2_000

    assert :ok =
             TestTransferConnection.control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert_receive {:test_stt_transport_started, transport, _}, 2_000

    TestSpeechToTextTransport.deliver(
      transport,
      ~s({"type":"Connected","request_id":"req","sequence_id":0})
    )

    assert_receive {:vxpipe_transfer_active, ^attempt_id},
                   2_000

    assert_receive {:DOWN, ^phase_monitor, :process, ^phase, :normal}, 2_000

    command = attachment_command(plan, room, support, "support-connection")

    assert {:ok, ingress} =
             TestTransferConnection.run(command, fn ->
               CallEngine.activate_speech_to_text(command)
             end)

    assert is_pid(ingress)

    assert {:ok, ^ingress} =
             TestTransferConnection.run(command, fn ->
               CallEngine.activate_speech_to_text(command)
             end)

    refute_receive {:test_stt_transport_started, _, _}

    assert {:error, %Vxpipe.CallEngine.Error{code: :connection_not_attached}} =
             CallEngine.activate_speech_to_text(%{command | actor_id: "wrong-actor"})

    foreign = start_supervised!({Agent, fn -> :ready end})

    assert {:error, %Vxpipe.CallEngine.Error{code: :connection_not_attached}} =
             Agent.get(foreign, fn _ -> CallEngine.activate_speech_to_text(command) end)
  end

  for completion <- [:accepted, :timed_out, :phase_lost] do
    @tag completion: completion
    test "an exact web destination hears its private briefing before #{completion}", %{
      completion: completion
    } do
      observe_transfer_phases()
      plan = compile_plan(wait_sounds: nil)
      caller = Map.fetch!(plan.participants, "caller")
      reception = Map.fetch!(plan.participants, "reception")
      support = Map.fetch!(plan.participants, "human-support")

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

      variables = CallVariables.whereis(room.incarnation_id)
      lifecycle = call_lifecycle(room.incarnation_id)

      assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

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
               attach_ready(plan, room, caller, "caller-connection", caller_sink)

      source_supervisor = participant_supervisor(plan, reception.participant_id)
      source_monitor = Process.monitor(source_supervisor)
      source_tts_monitor = Process.monitor(source_tts)

      assert :ok =
               Vxpipe.CallEngine.TestTransferConnection.send_text(
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
               CallEngine.participant_snapshot(
                 plan.tenant_id,
                 plan.room_id,
                 support.participant_id
               )

      assert {:ok,
              %ConnectionAttachment{
                admission: :transfer_preparation,
                room_audio_input_mode: :disabled,
                room_audio_output_mode: :disabled,
                transfer_attempt_id: attempt_id
              } = pending_attachment} =
               attach_ready(plan, room, support, "support-connection", support_sink)

      assert is_binary(attempt_id)
      assert :disabled = CallEngine.room_audio_configuration(pending_attachment)
      assert :disabled = CallEngine.room_audio_output_configuration(pending_attachment)

      assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt_id, :accept)
               )

      refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "human-support-transfer"}},
                     50

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt_id, :media_ready)
               )

      authority = room_authority(plan)
      await_transfer_preparation(authority, System.monotonic_time(:millisecond) + 2_000)
      pending = :sys.get_state(authority).pending_participant_transfer
      briefing = pending.preparation.text_to_speech
      briefing_monitor = Process.monitor(briefing.pid)
      transport_monitor = Process.monitor(briefing_tts)
      briefing_request = pending.briefing_request

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

      refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "human-support-transfer"}},
                     50

      refute_receive {:DOWN, ^briefing_monitor, :process, _, _}, 50
      assert :ok = TestAudioOutputSink.playback_started(support_sink)
      assert :ok = TestAudioOutputSink.playback_completed(support_sink)

      usage_facts = collect_tts_usage(2)

      assert Enum.all?(usage_facts, fn fact ->
               fact.call_id == plan.call_id and
                 fact.participant_id == support.participant_id and
                 fact.activation_id == nil and
                 fact.payload["provider"]["name"] == "deepgram" and
                 fact.payload["provider"]["integration_id"] ==
                   Vxpipe.CallEngine.CallSpec.CapabilitySelection.identity(
                     plan.participants[plan.entry_receiver].capabilities.text_to_speech,
                     plan.tenant_id
                   ) and
                 fact.payload["provider"]["request_id"] == "private-briefing" and
                 fact.payload["provider"]["operation_id"] == nil
             end)

      assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt_id}, 2_000

      assert_receive {:transfer_phase, %{duration: briefing_duration},
                      %{phase: :briefing, outcome: :ok}},
                     1_000

      assert briefing_duration >= 0
      refute_receive {:transfer_phase, _, %{phase: :acceptance}}, 0
      assert_receive {:DOWN, ^briefing_monitor, :process, _, _}, 1_000
      assert_receive {:DOWN, ^transport_monitor, :process, ^briefing_tts, _}, 1_000
      refute_receive {:DOWN, ^source_tts_monitor, :process, ^source_tts, _}, 50

      # Delayed notifications from retired private speech cannot cancel the live attempt.
      send(authority, {:vxpipe_tts_playback, briefing.pid, briefing_request, :completed})
      send(authority, {:vxpipe_tts_unavailable, briefing.pid, :transport_closed})
      send(authority, {:DOWN, briefing.monitor, :process, briefing.pid, :shutdown})
      _ = :sys.get_state(authority)
      refute_receive {:vxpipe_transfer_acceptance_ready, ^attempt_id}, 50
      refute_receive {:vxpipe_transfer_progress, ^attempt_id, %{phase: :recovering}}, 50

      if completion == :accepted do
        assert :ok =
                 TestTransferConnection.control(
                   transfer_control(plan, room, support, attempt_id, :accept)
                 )

        assert_receive {:transfer_phase, %{duration: acceptance_duration},
                        %{phase: :acceptance, outcome: :ok}},
                       1_000

        assert acceptance_duration >= 0

        assert_receive {:vxpipe_transfer_active, ^attempt_id},
                       2_000

        for _listener <- [:caller, :support] do
          assert_receive {:transfer_phase, %{duration: cue_duration},
                          %{phase: :cue, outcome: :ok}},
                         1_000

          assert cue_duration >= 0
        end

        refute_receive {:transfer_phase, _, %{phase: :briefing}}, 0
        refute_receive {:transfer_phase, _, %{phase: :acceptance}}, 0

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
                 CallEngine.participant_snapshot(
                   plan.tenant_id,
                   plan.room_id,
                   support.participant_id
                 )

        assert support_snapshot.participant_id == support.participant_id
        assert CallVariables.whereis(room.incarnation_id) == variables
        assert call_lifecycle(room.incarnation_id) == lifecycle
        assert AgentActivationSupervisor.whereis_child(reception.activation_id, :session) == nil
      else
        pending = :sys.get_state(authority).pending_participant_transfer
        assert :ok = GenServer.call(caller_sink, {:defer_drain, true})

        outcome =
          case completion do
            :timed_out ->
              send(authority, {:vxpipe_participant_transfer_deadline, pending.task.ref})
              :timeout

            :phase_lost ->
              Process.exit(pending.task.pid, :kill)
              :terminated
          end

        assert_receive {:transfer_phase, %{duration: duration},
                        %{phase: :acceptance, outcome: ^outcome}},
                       1_000

        assert duration >= 0

        assert_receive {:test_audio_output_drain, ^caller_sink}, 1_000
        recovering = :sys.get_state(authority).pending_participant_transfer
        assert recovering.handoff.stage == :recovering
        assert recovering.preparation == nil

        # Retirement notifications can arrive after the failed preparation was discarded.
        send(authority, {:vxpipe_tts_playback, briefing.pid, briefing_request, :completed})
        send(authority, {:vxpipe_tts_unavailable, briefing.pid, :transport_closed})
        send(authority, {:DOWN, briefing.monitor, :process, briefing.pid, :shutdown})
        assert :sys.get_state(authority).pending_participant_transfer == recovering
        assert :ok = GenServer.call(caller_sink, :complete_drain)

        assert_receive {:vxpipe_event, %ToolCallFailed{tool_call_id: "human-support-transfer"}},
                       2_000

        assert_receive {:transfer_phase, _, %{phase: :cue, outcome: :ok}}, 1_000
        refute_receive {:transfer_phase, _, %{phase: :acceptance}}, 0
        refute_receive {:transfer_phase, _, %{phase: :briefing}}, 0
        refute_receive {:DOWN, ^source_tts_monitor, :process, ^source_tts, _}, 0
        assert :sys.get_state(authority).pending_participant_transfer == nil
      end
    end
  end

  test "only the exact destination connection can control the current attempt" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :control_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :control_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach_ready(plan, room, caller, "caller-connection", caller_sink)

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

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
             CallEngine.participant_transfer_control(exact)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
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

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :drop_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :drop_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach_ready(plan, room, caller, "caller-connection", caller_sink)

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

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :timeout_caller_sink)

    support_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :timeout_support_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             attach_ready(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller, "timed-out-human-transfer")
    assert_receive {:test_tts_transport_started, _briefing_tts, _connection}, 2_000

    assert {:ok,
            %ConnectionAttachment{
              admission: :transfer_preparation,
              transfer_attempt_id: attempt_id
            }} = attach(plan, room, support, "support-connection", support_sink)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
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
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :commit_caller)
    support_sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :commit_support)

    assert {:ok, caller_attachment} =
             attach_ready(plan, room, caller, "caller-connection", caller_sink)

    enforcer =
      start_supervised!({Vxpipe.CallEngine.TestMediaPolicyEnforcer, owner: self(), mode: :ok})

    assert {:ok, _} =
             TestTransferConnection.run(
               attachment_command(plan, room, caller, "caller-connection"),
               fn -> CallEngine.register_room_audio_enforcer(caller_attachment, enforcer) end
             )

    assert_receive {:media_policy_applied, ^enforcer, _}

    begin_transfer(plan, room, caller, "phase-lost-during-commit")
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

    assert {:ok, %ConnectionAttachment{transfer_attempt_id: attempt_id}} =
             attach_ready(plan, room, support, "support-connection", support_sink)

    authority = room_authority(plan)
    authority_monitor = Process.monitor(authority)
    phase = :sys.get_state(authority).pending_participant_transfer.task.pid
    phase_monitor = Process.monitor(phase)
    assert {:ok, _} = Phase.scope(phase)

    :sys.replace_state(enforcer, &%{&1 | mode: :manual})

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
             TestTransferConnection.control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert :ok =
             TestTransferConnection.control(
               transfer_control(plan, room, support, attempt_id, :media_ready)
             )

    finish_private_briefing(briefing_tts, support_sink)
    assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt_id}, 2_000

    assert :ok =
             TestTransferConnection.control(
               transfer_control(plan, room, support, attempt_id, :accept)
             )

    assert_receive {:media_policy_applied, ^enforcer, _}, 2_000
    Process.exit(phase, :kill)
    assert_receive {:DOWN, ^phase_monitor, :process, ^phase, :killed}, 2_000
    Vxpipe.CallEngine.TestMediaPolicyEnforcer.acknowledge(enforcer, :ok)

    refute_receive {:vxpipe_transfer_progress, ^attempt_id, %{phase: :recovering}}, 100

    assert_receive {:DOWN, ^authority_monitor, :process, ^authority, :handoff_release_failed},
                   2_000

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "phase-lost-during-commit"}}
    refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _}
  end

  for failure <- [:reject, :authority_exit] do
    @tag capture_log: true, barrier_failure: failure
    test "privacy barrier #{failure} closes the room before bridge or source handoff", %{
      barrier_failure: failure
    } do
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

      assert {:ok, room} =
               Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive_options())

      assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      assert [{room_authority, _value}] =
               Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

      room_monitor = Process.monitor(room_authority)

      caller_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :policy_caller_sink)

      support_sink =
        start_supervised!({TestAudioOutputSink, observer: self()}, id: :policy_support_sink)

      assert {:ok, %ConnectionAttachment{admission: :main} = caller_attachment} =
               attach_ready(plan, room, caller, "caller-connection", caller_sink)

      begin_transfer(plan, room, caller, "policy-failed-human-transfer")
      assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

      assert {:ok,
              %ConnectionAttachment{
                admission: :transfer_preparation,
                transfer_attempt_id: attempt_id
              }} = attach_ready(plan, room, support, "support-connection", support_sink)

      enforcer =
        start_supervised!({Vxpipe.CallEngine.TestMediaPolicyEnforcer, owner: self(), mode: :ok})

      assert {:ok, _} =
               TestTransferConnection.run(
                 attachment_command(plan, room, caller, "caller-connection"),
                 fn -> CallEngine.register_room_audio_enforcer(caller_attachment, enforcer) end
               )

      assert_receive {:media_policy_applied, ^enforcer, _}
      mode = if failure == :reject, do: {:error, :privacy_barrier_failed}, else: :manual
      :sys.replace_state(enforcer, &%{&1 | mode: mode})

      assert {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt_id, :accept)
               )

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt_id, :media_ready)
               )

      finish_private_briefing(briefing_tts, support_sink)
      assert_receive {:vxpipe_transfer_acceptance_ready, ^attempt_id}, 2_000

      assert :ok =
               TestTransferConnection.control(
                 transfer_control(plan, room, support, attempt_id, :accept)
               )

      if failure == :authority_exit do
        assert_receive {:media_policy_applied, ^enforcer, _candidate}, 1_000
        Process.exit(PolicyAuthority.whereis(room.incarnation_id), :kill)
      end

      assert_receive {:vxpipe_transfer_progress, ^attempt_id, %{phase: :failed}}, 1_000

      assert_receive {:test_archive_fact,
                      %Fact{
                        kind: :participant_transfer_failed,
                        tool_call_id: "policy-failed-human-transfer",
                        payload: %{
                          "cause" => "destination_commit_unavailable",
                          "restoration" => "failed"
                        }
                      }},
                     1_000

      assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :handoff_commit_failed},
                     2_000

      refute_receive {:vxpipe_transfer_main_media, ^attempt_id, _attachment}, 50

      refute_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "policy-failed-human-transfer"}},
                     50
    end
  end

  defp observe_transfer_phases do
    token = make_ref()
    event = [:vxpipe, :call_engine, :transfer, :phase, :stop]
    owner = self()

    assert :ok =
             :telemetry.attach(
               token,
               event,
               fn _, measurements, metadata, _ ->
                 send(owner, {:transfer_phase, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(token) end)
  end

  defp observe_transfer_workers(authority) do
    token = make_ref()
    owner = self()

    assert :ok =
             :telemetry.attach(
               token,
               [:vxpipe, :call_engine, :transfer, :worker, :stop],
               fn _, measurements, metadata, _ ->
                 if self() == authority,
                   do: send(owner, {:transfer_worker, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(token) end)
  end

  defp pause_handoff_result(worker, stage \\ :prepare) do
    token = make_ref()
    event = [:vxpipe, :call_engine, :transfer, :phase, :stop]

    assert :ok =
             :telemetry.attach(
               token,
               event,
               fn _event, _measurements, metadata, owner ->
                 if self() == worker and metadata.phase == stage and metadata.outcome == :ok do
                   send(owner, {:handoff_result_ready, token})

                   receive do
                     {:continue_handoff, ^token} -> :ok
                   after
                     2_000 -> :ok
                   end
                 end
               end,
               self()
             )

    on_exit(fn -> :telemetry.detach(token) end)
    token
  end

  defp connect_policy_observer(plan, room) do
    observer = Map.fetch!(plan.participants, "observer")

    assert {:ok, join} =
             CallEngine.Command.JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: observer.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _participant} = CallEngine.join_participant(join)
    sink = start_supervised!({TestAudioOutputSink, observer: self()}, id: :cue_observer)
    assert {:ok, _} = attach_ready(plan, room, observer, "observer-connection", sink)

    assert {:ok, _policy} =
             PolicyAuthority.leave(
               PolicyAuthority.whereis(room.incarnation_id),
               observer.participant_id
             )

    observer.participant_id
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
        do:
          Map.put(support, :capabilities, %{
            speech_to_text: %{
              provider: "deepgram",
              model: "flux-general-en",
              options: %{encoding: "opus", sample_rate: 48_000}
            }
          }),
        else: support

    support =
      case Keyword.get(options, :support_while_present) do
        nil -> support
        policy -> Map.put(support, :while_present, policy)
      end

    assert {:ok, call_spec} =
             CallSpec.new(
               %{
                 schema_version: CallSpec.schema_version(),
                 wait_sounds:
                   case Keyword.get(options, :wait_sounds, %{}) do
                     nil -> nil
                     sounds -> Map.put(sounds, :call_setup, nil)
                   end,
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
                       model_inference: %{provider: "fixture", model: "test:scripted"},
                       text_to_speech: %{
                         provider: "deepgram",
                         model: "flux-test-voice",
                         credential_name:
                           Keyword.get(options, :speech_credential_name, "default"),
                         options: %{
                           encoding: "linear16",
                           sample_rate: 48_000
                         }
                       }
                     },
                     tools: %{},
                     transfers: ["human-support"]
                   },
                   "human-support" => support,
                   "observer" => %{
                     type: "human",
                     connection: %{service: "web", mode: "receive", admission: "start_call"},
                     while_present: Keyword.get(options, :observer_policy, %{})
                   }
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "human-transfer-call-spec",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "human-transfer-call-spec", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-human-transfer",
               actor_id: "actor-human-transfer",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{
               host_tools: %{}
             })

    plan
  end

  defp attach(plan, room, participant, connection_id, output_sink) do
    command = attachment_command(plan, room, participant, connection_id)
    CallEngine.attach_connection(command, output_sink)
  end

  defp attach_ready(plan, room, participant, connection_id, output_sink) do
    with {:ok, attachment} <-
           TestTransferConnection.attach(
             attachment_command(plan, room, participant, connection_id),
             output_sink
           ) do
      if participant.call_spec_key == plan.entry_caller,
        do: Vxpipe.CallEngine.TestCallStartup.await_ready(plan.room_id)

      {:ok, attachment}
    end
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
    submit_transfer(plan, room, caller, tool_call_id)
    await_transfer_preparation(room_authority(plan), System.monotonic_time(:millisecond) + 2_000)
  end

  defp submit_transfer(plan, room, caller, tool_call_id) do
    assert :ok =
             Vxpipe.CallEngine.TestTransferConnection.send_text(
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

  defp await_transfer_preparation(authority, deadline) do
    case :sys.get_state(authority).pending_participant_transfer do
      %{preparation: preparation} when not is_nil(preparation) ->
        :ok

      _pending ->
        assert System.monotonic_time(:millisecond) < deadline,
               "the authoritative transfer preparation did not finish"

        receive do
        after
          10 -> await_transfer_preparation(authority, deadline)
        end
    end
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
