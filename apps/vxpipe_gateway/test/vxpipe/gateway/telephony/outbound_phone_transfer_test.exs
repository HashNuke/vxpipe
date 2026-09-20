defmodule Vxpipe.Gateway.Telephony.OutboundPhoneTransferTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    ConnectionAttachment,
    TestAudioOutputSink,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed}
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.Telephony.{EndLeg, LegReference}

  alias Vxpipe.Gateway.Telephony.{
    LegSupervisor,
    MediaSupervisor,
    OutgoingLeg
  }

  alias Vxpipe.Gateway.{PhoneTransferScenario, TestTelephonySocket}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech.Session,
      provider_options: [
        api_key: "runtime-test-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      wire_module: TestTextToSpeechTransport,
      wire_options: [observer: self()],
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "the exact outbound phone leg accepts with press 1 after its private briefing" do
    assert_private_transfer(:telnyx)
  end

  test "Twilio runs the same private press-1 transfer contract" do
    assert_private_transfer(:twilio)
  end

  for provider <- [:telnyx, :twilio] do
    test "#{provider} prepares private decoder and output before room admission" do
      assert_private_preparation(unquote(provider))
    end
  end

  defp assert_private_preparation(provider) do
    alias Vxpipe.CallEngine.Media.{ConnectionReadiness, OutputSink}
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.Collector
    alias Vxpipe.CallEngine.RoomMixer
    alias Vxpipe.Gateway.Telephony.MediaSession

    plan = PhoneTransferScenario.compile_plan(provider)
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    leg_id = PhoneTransferScenario.unique_id("private-phone")
    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)
    connector = PhoneTransferScenario.connector(provider, plan.tenant_id, self(), leg_id)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, outbound_leg_connector: connector)

    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink = start_supervised!({TestAudioOutputSink, observer: self()})

    assert {:ok, _attachment} =
             PhoneTransferScenario.attach(plan, room, caller, "caller-connection", caller_sink)

    begin_transfer(plan, room, caller)
    assert_dial(provider, leg_id)
    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"Connected","request_id":"briefing-ready"})
    )

    await_transfer_preparation(plan, System.monotonic_time(:millisecond) + 2_000)
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(leg_id)
    socket = start_supervised!({TestTelephonySocket, observer: self()})
    event = PhoneTransferScenario.media_started_event(provider, leg_id)

    assert :ok =
             TestTelephonySocket.run(socket, fn -> OutgoingLeg.dispatch(leg, event, 5_000) end)

    assert {:ok, snapshot} = MediaSupervisor.snapshot(leg_id)
    attempt_id = snapshot.attachment.transfer_attempt_id

    [{session, _}] =
      Registry.lookup(Vxpipe.Gateway.Media.Registry, {:telephony_media_session, leg_id})

    assert :ok =
             TestTelephonySocket.bind_readiness(
               socket,
               :sys.get_state(session).binding,
               event.stream_id
             )

    assert {:error, _} = MediaSession.prepare_transfer_media(session, "stale")
    assert {:ok, private} = MediaSession.prepare_transfer_media(session, attempt_id)
    assert {:ok, ^private} = MediaSession.prepare_transfer_media(session, attempt_id)
    {:ok, binding} = GenServer.call(session, :vxpipe_connection_readiness)
    assert binding.output == snapshot.audio_output
    assert binding.attachment == snapshot.attachment
    assert binding.attachment.media_ingress == nil
    assert :sys.get_state(binding.room_input).pipeline_pid == nil
    assert :sys.get_state(binding.room_output).pipeline_pid == nil
    assert length(private.enforcers) == 2

    authority = Authority.whereis(room.incarnation_id)
    policy = Authority.snapshot(authority)

    presence =
      policy.present_participant_ids
      |> MapSet.delete(Map.fetch!(plan.participants, "reception").participant_id)
      |> MapSet.put(support.participant_id)

    assert {:ok, candidate} = Authority.preview_presence(authority, presence)
    assert :ok = OutputSink.hold(binding.output, 1)

    options = [
      owner: private.owner,
      attempt_id: attempt_id,
      deadline_ms: private.deadline_ms,
      generation: 1,
      subscriptions: [binding.policy_subscription]
    ]

    mixer = RoomMixer.whereis(room.incarnation_id)
    assert {:ok, prepared_mixer} = RoomMixer.prepare_policy(mixer, candidate, options)
    subscription = Map.fetch!(prepared_mixer.subscriptions, leg_id <> ":room-output")

    assert {:ok, graph} =
             ConnectionReadiness.prepare_candidate(
               session,
               binding.identity,
               candidate,
               [audio_input?: true, room_output?: true, speech_to_text?: false],
               Keyword.put(options, :subscription, subscription)
             )

    expected_format =
      case provider do
        :telnyx -> %{codec: :opus, sample_rate: 16_000, channels: 1}
        :twilio -> %{codec: :pcmu, sample_rate: 8_000, channels: 1}
      end

    assert graph.input_track == Map.put(expected_format, :track_id, event.stream_id)
    refute Enum.any?(graph.resources, &(&1.kind == :speech_to_text))

    collector =
      start_supervised!(
        {Collector,
         Keyword.merge(options,
           owner: self(),
           incarnation_id: room.incarnation_id,
           resources: Enum.uniq(prepared_mixer.resources ++ graph.resources)
         )}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    assert Authority.snapshot(authority) == policy
    assert {:ok, current} = MediaSupervisor.snapshot(leg_id)
    assert current.attachment == snapshot.attachment
    assert :ok = ConnectionReadiness.discard_candidate(graph)
    assert :ok = RoomMixer.discard_policy(mixer, prepared_mixer.token)
    stop_supervised!({Collector, attempt_id})

    monitors = Enum.map([session | private.enforcers], &{&1, Process.monitor(&1)})
    Process.exit(private.owner, :kill)

    for {actor, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^actor, _reason}, 2_000
    end

    assert Authority.snapshot(authority) == policy
  end

  defp assert_private_transfer(provider) when provider in [:telnyx, :twilio] do
    plan = PhoneTransferScenario.compile_plan(provider)
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    leg_id = PhoneTransferScenario.unique_id("outbound-leg")
    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    connector = PhoneTransferScenario.connector(provider, plan.tenant_id, self(), leg_id)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, outbound_leg_connector: connector)

    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :outbound_phone_caller_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             PhoneTransferScenario.attach(
               plan,
               room,
               caller,
               "caller-connection",
               caller_sink
             )

    begin_transfer(plan, room, caller)

    assert_dial(provider, leg_id)
    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"Connected","request_id":"briefing-ready"})
    )

    await_transfer_preparation(plan, System.monotonic_time(:millisecond) + 2_000)
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(leg_id)

    socket = start_supervised!({TestTelephonySocket, observer: self()})

    media_started = PhoneTransferScenario.media_started_event(provider, leg_id)

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(
                 leg,
                 media_started,
                 5_000
               )
             end)

    [{session, _}] =
      Registry.lookup(Vxpipe.Gateway.Media.Registry, {:telephony_media_session, leg_id})

    assert :ok =
             TestTelephonySocket.bind_readiness(
               socket,
               :sys.get_state(session).binding,
               media_started.stream_id
             )

    assert {:ok,
            %{
              attachment: %ConnectionAttachment{
                admission: :transfer_preparation,
                room_audio_input_mode: :disabled,
                room_audio_output_mode: :disabled,
                transfer_attempt_id: attempt_id
              }
            }} = MediaSupervisor.snapshot(leg_id)

    assert is_binary(attempt_id)
    assert_receive {:test_tts_control, ^briefing_tts, speak}, 2_000

    assert JSON.decode!(speak) == %{
             "text" => "Taylor is calling about order 17. This call is recorded.",
             "type" => "Speak"
           }

    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    assert {:error, :wrong_media_source} =
             OutgoingLeg.dispatch(
               leg,
               PhoneTransferScenario.dtmf_event(provider, leg_id, "1"),
               5_000
             )

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(
                 leg,
                 PhoneTransferScenario.dtmf_event(provider, leg_id, "1"),
                 5_000
               )
             end)

    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "phone-transfer"}}, 50

    PhoneTransferScenario.finish_private_briefing(briefing_tts)

    message = receive_media(provider)
    assert %{"event" => "media"} = JSON.decode!(message)

    assert_eventually(fn ->
      match?({:ok, %{transfer_acceptance_ready?: true}}, MediaSupervisor.snapshot(leg_id))
    end)

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(
                 leg,
                 PhoneTransferScenario.dtmf_event(provider, leg_id, "1"),
                 5_000
               )
             end)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "phone-transfer",
                      result: %{
                        "destination" => "human-support",
                        "status" => "completed"
                      }
                    }},
                   2_000

    assert_eventually(fn ->
      match?(
        {:ok,
         %{
           attachment: %ConnectionAttachment{
             admission: :main,
             room_audio_input_mode: :enabled,
             room_audio_output_mode: :mix_minus
           },
           room_audio_ingress: ingress,
           room_audio_egress: egress
         }}
        when is_pid(ingress) and is_pid(egress),
        MediaSupervisor.snapshot(leg_id)
      )
    end)

    assert :ok =
             TestTelephonySocket.run(socket, fn ->
               OutgoingLeg.dispatch(
                 leg,
                 PhoneTransferScenario.dtmf_event(provider, leg_id, "1"),
                 5_000
               )
             end)

    assert {:ok, snapshot} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, support.participant_id)

    assert snapshot.participant_id == support.participant_id
  end

  test "a configured machine result ends only the attempted destination and retains the source" do
    assert_machine_transfer_failure(:telnyx)
  end

  test "Twilio machine detection ends only the attempted destination and retains the source" do
    assert_machine_transfer_failure(:twilio)
  end

  defp assert_machine_transfer_failure(provider) when provider in [:telnyx, :twilio] do
    plan = PhoneTransferScenario.compile_plan(provider)
    caller = Map.fetch!(plan.participants, "caller")
    reception = Map.fetch!(plan.participants, "reception")
    leg_id = PhoneTransferScenario.unique_id("outbound-machine-leg")
    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    connector =
      PhoneTransferScenario.connector(
        provider,
        plan.tenant_id,
        self(),
        leg_id,
        answering_machine_detection: :detect
      )

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan, outbound_leg_connector: connector)

    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :machine_caller_sink)

    assert {:ok, %ConnectionAttachment{admission: :main}} =
             PhoneTransferScenario.attach(
               plan,
               room,
               caller,
               "caller-connection",
               caller_sink
             )

    begin_transfer(plan, room, caller)

    assert_detecting_dial(provider, leg_id)

    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"Connected","request_id":"briefing-ready"})
    )

    await_transfer_preparation(plan, System.monotonic_time(:millisecond) + 2_000)
    assert {:ok, leg} = LegSupervisor.lookup_outgoing(leg_id)
    monitor = Process.monitor(leg)

    assert :ok =
             OutgoingLeg.dispatch(
               leg,
               PhoneTransferScenario.answering_machine_event(provider),
               1_000
             )

    assert_machine_end(provider, leg_id)

    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 2_000

    assert_receive {:vxpipe_event,
                    %ToolCallFailed{tool_call_id: "phone-transfer", reason: :tool_failed}},
                   2_000

    assert {:ok, source} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               reception.participant_id
             )

    assert source.participant_id == reception.participant_id
    refute_duplicate_end(provider)
  end

  defp begin_transfer(plan, room, caller) do
    assert :ok =
             Vxpipe.CallEngine.TestTransferConnection.send_text(
               PhoneTransferScenario.send_command(
                 plan,
                 room,
                 caller,
                 "Please connect me to human support."
               )
             )

    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "phone-transfer",
               name: "transfer",
               arguments: %{
                 "destination" => "human-support",
                 "reason" => "Taylor is calling about order 17."
               }
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_dial(:telnyx, leg_id) do
    assert_receive {:test_telephony_dial, %{leg_id: ^leg_id}}, 2_000
  end

  defp assert_dial(:twilio, leg_id) do
    assert_receive {:test_twilio_dial, %{leg_id: ^leg_id}}, 2_000
  end

  defp assert_detecting_dial(:telnyx, leg_id) do
    assert_receive {:test_telephony_dial,
                    %{leg_id: ^leg_id, answering_machine_detection: :detect}},
                   2_000
  end

  defp assert_detecting_dial(:twilio, leg_id) do
    assert_receive {:test_twilio_dial, %{leg_id: ^leg_id, answering_machine_detection: :detect}},
                   2_000
  end

  defp assert_machine_end(:telnyx, leg_id) do
    assert_receive {:test_telephony_end_leg,
                    %EndLeg{
                      leg: %LegReference{leg_id: ^leg_id},
                      reason: :answering_machine
                    }},
                   2_000
  end

  defp assert_machine_end(:twilio, leg_id) do
    assert_receive {:test_twilio_end_leg,
                    %EndLeg{
                      leg: %LegReference{leg_id: ^leg_id},
                      reason: :answering_machine
                    }},
                   2_000
  end

  defp refute_duplicate_end(:telnyx), do: refute_receive({:test_telephony_end_leg, _duplicate})
  defp refute_duplicate_end(:twilio), do: refute_receive({:test_twilio_end_leg, _duplicate})

  defp receive_media(:telnyx) do
    assert_receive {:test_telnyx_socket_send, message}, 2_000
    message
  end

  defp receive_media(:twilio) do
    assert_receive {:test_twilio_socket_send, message}, 2_000
    message
  end

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      receive do
      after
        10 -> assert_eventually(assertion, attempts - 1)
      end
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")

  defp await_transfer_preparation(plan, deadline) do
    [{authority, _value}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    case :sys.get_state(authority).pending_participant_transfer do
      %{preparation: preparation} when not is_nil(preparation) ->
        :ok

      _pending ->
        assert System.monotonic_time(:millisecond) < deadline,
               "transfer preparation did not finish after private text-to-speech became ready"

        receive do
        after
          10 -> await_transfer_preparation(plan, deadline)
        end
    end
  end
end
