defmodule Vxpipe.Gateway.Telephony.TelnyxCallHarnessTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  alias Vxpipe.CallEngine.{
    TestSelectiveAgentRuntimeModelProvider,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.TestTelephonySocket

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    LegSupervisor,
    MediaAdmission,
    MediaSupervisor
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.{ClientState, MediaSocket}

  alias Vxpipe.Gateway.{
    TelnyxCallScenario,
    TelnyxFixture,
    TelephonyHarnessBackend
  }

  @incoming_leg_id "leg-inbound-harness"
  @outgoing_leg_id "leg-outbound-harness"
  @ingress_key "harness"
  @received_at DateTime.to_unix(~U[2026-09-11 15:00:05Z])

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestSelectiveAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

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

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [api_key: "runtime-test-secret"],
      transport: {TestSpeechToTextTransport, [observer: self()]},
      media_ingress: [
        maximum_frames: 8,
        maximum_bytes: 1_024,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 2
      ]
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    admission = start_supervised!({MediaAdmission, name: nil})

    scenario =
      TelnyxCallScenario.build(
        self(),
        public_key,
        admission,
        @incoming_leg_id,
        @outgoing_leg_id
      )

    backend =
      start_supervised!(
        {TelephonyHarnessBackend,
         claim: scenario.claim, runtime_options: scenario.runtime_options}
      )

    endpoint =
      Endpoint.init(
        telephony: [
          enabled: true,
          clock: fn -> @received_at end,
          handler: {CallIngress, backend: TelephonyHarnessBackend.backend(backend)},
          media_admission: admission,
          services: [scenario.service_options]
        ]
      )

    on_exit(fn ->
      stop_room(scenario.plan.tenant_id, scenario.plan.room_id)
      LegSupervisor.stop(:telnyx, "primary-phone", "inbound-call-leg")
      LegSupervisor.stop_outgoing(@outgoing_leg_id)
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    %{
      backend: backend,
      endpoint: endpoint,
      plan: scenario.plan,
      private_key: private_key
    }
  end

  test "runs one signed inbound call through private press-1 phone transfer after storage loss",
       context do
    incoming = post_fixture(context, "call-initiated-incoming")
    assert incoming.status == 200

    assert_receive {:test_tts_transport_started, _source_tts, _connection}, 2_000
    assert_receive {:test_telephony_answer, answer}, 2_000
    refute_receive {:test_telephony_answer, _duplicate}

    duplicate = post_fixture(context, "call-initiated-incoming")
    assert duplicate.status == 200
    refute_receive {:test_telephony_answer, _duplicate}

    :ok = TelephonyHarnessBackend.make_storage_unavailable(context.backend)

    answered = post_fixture(context, "call-answered-incoming")
    assert answered.status == 200

    inbound_transport =
      start_supervised!({TestTelephonySocket, observer: self()}, id: :incoming_socket)

    outbound_transport =
      start_supervised!({TestTelephonySocket, observer: self()}, id: :outgoing_socket)

    assert {:ok, inbound_binding, inbound_socket} =
             TestTelephonySocket.open(inbound_transport, MediaSocket, fn ->
               TelnyxFixture.open_media(context.endpoint, answer.media_url, %{
                 "call_control_id" => "inbound-call-control",
                 "call_session_id" => "inbound-call-session",
                 "client_state" => ClientState.encode(@incoming_leg_id),
                 "from" => "+15550001001",
                 "stream_id" => "inbound-stream",
                 "to" => "+15550001000"
               })
             end)

    assert inbound_binding.client_state_leg_id == @incoming_leg_id
    assert {:ok, %{attachment: %{admission: :main}}} = MediaSupervisor.snapshot(@incoming_leg_id)
    assert_receive {:test_stt_transport_started, stt_transport, _connection}, 2_000

    begin_transfer(stt_transport, inbound_transport)

    assert_receive {:test_telephony_dial, dial}, 2_000
    assert dial.leg_id == @outgoing_leg_id
    assert dial.to == "+15550001002"

    outgoing_client_state = ClientState.encode(@outgoing_leg_id)

    assert post_fixture(context, "call-initiated-outgoing", %{
             "client_state" => outgoing_client_state
           }).status == 200

    assert post_fixture(context, "call-initiated-outgoing", %{
             "client_state" => outgoing_client_state
           }).status == 200

    refute_receive {:test_telephony_dial, _duplicate}

    assert {:ok, _outbound_binding, _outbound_socket} =
             TestTelephonySocket.open(outbound_transport, MediaSocket, fn ->
               TelnyxFixture.open_media(context.endpoint, dial.media_url, %{
                 "call_control_id" => "outbound-call-control",
                 "call_session_id" => "outbound-call-session",
                 "client_state" => outgoing_client_state,
                 "from" => "+15550001000",
                 "stream_id" => "outbound-stream",
                 "to" => "+15550001002"
               })
             end)

    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    assert {:ok, _outbound_socket} =
             TestTelephonySocket.input(
               outbound_transport,
               {TelnyxFixture.body("media-dtmf", %{
                  "digit" => "1",
                  "stream_id" => "outbound-stream"
                }), opcode: :text}
             )

    assert {:ok, %{attachment: %{admission: :transfer_preparation}}} =
             MediaSupervisor.snapshot(@outgoing_leg_id)

    reception = Map.fetch!(context.plan.participants, "reception")

    [{source_agent, _value}] =
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {:participant, context.plan.tenant_id, context.plan.room_id, reception.participant_id}
      )

    source_monitor = Process.monitor(source_agent)
    finish_private_briefing(briefing_tts)

    assert {:ok, %{transfer_acceptance_ready?: true}} = await_transfer_state(:acceptance_ready)

    assert {:ok, _socket} =
             TestTelephonySocket.input(
               outbound_transport,
               {TelnyxFixture.body("media-dtmf", %{
                  "digit" => "1",
                  "stream_id" => "outbound-stream",
                  "sequence_number" => 100
                }), opcode: :text}
             )

    assert_receive {:DOWN, ^source_monitor, :process, ^source_agent, _reason}, 2_000

    assert_receive {:test_phone_output, ^outbound_transport, output}, 2_000

    assert %{"event" => "media"} = JSON.decode!(output)

    assert {:ok, %{attachment: %{admission: :main}}} = await_transfer_state(:main)

    caller = Map.fetch!(context.plan.participants, "caller")
    support = Map.fetch!(context.plan.participants, "human-support")

    assert {:ok, caller_snapshot} =
             Vxpipe.CallEngine.participant_snapshot(
               context.plan.tenant_id,
               context.plan.room_id,
               caller.participant_id
             )

    assert {:ok, support_snapshot} =
             Vxpipe.CallEngine.participant_snapshot(
               context.plan.tenant_id,
               context.plan.room_id,
               support.participant_id
             )

    assert caller_snapshot.state == :joined
    assert support_snapshot.state == :joined

    claim_count =
      Enum.count(TelephonyHarnessBackend.operations(context.backend), fn
        {:claim_incoming, _event_id} -> true
        _operation -> false
      end)

    assert claim_count == 1
    assert inbound_socket.stream_id == "inbound-stream"
  end

  defp post_fixture(context, name, replacements \\ %{}) do
    TelnyxFixture.post_event(
      context.endpoint,
      context.private_key,
      @ingress_key,
      name,
      replacements,
      @received_at
    )
  end

  defp begin_transfer(stt_transport, socket) do
    TestSpeechToTextTransport.deliver(
      stt_transport,
      ~s({"type":"Connected","request_id":"request-telnyx-harness","sequence_id":0})
    )

    assert_caller_audio(stt_transport, socket)

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("StartOfTurn", 1, "Please connect me to human support.")
    )

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("EndOfTurn", 2, "Please connect me to human support.", "model")
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

  defp assert_caller_audio(stt_transport, socket) do
    encoder = Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)

    assert {:ok, payload} =
             Membrane.Opus.Encoder.Native.encode_packet(
               encoder,
               :binary.copy(<<0::16>>, 320),
               320
             )

    message = %{
      "event" => "media",
      "stream_id" => "inbound-stream",
      "sequence_number" => 2,
      "media" => %{
        "track" => "inbound",
        "chunk" => 1,
        "timestamp" => 0,
        "payload" => Base.encode64(payload)
      }
    }

    assert {:ok, _socket} =
             TestTelephonySocket.input(socket, {JSON.encode!(message), opcode: :text})

    assert_receive {:test_stt_audio, ^stt_transport, ^payload}, 2_000
  end

  defp turn_message(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-telnyx-harness",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if trigger == nil, do: message, else: Map.put(message, "trigger", trigger)
    JSON.encode!(message)
  end

  defp finish_private_briefing(briefing_tts) do
    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(
      briefing_tts,
      :binary.copy(<<1_000::little-signed-16>>, 960)
    )

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )
  end

  defp stop_room(tenant_id, room_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}) do
      [{room, _value}] -> Process.exit(room, :shutdown)
      [] -> :ok
    end
  end

  defp await_transfer_state(expected) do
    await_transfer_state(expected, System.monotonic_time(:millisecond) + 2_000)
  end

  defp await_transfer_state(expected, deadline) do
    result = MediaSupervisor.snapshot(@outgoing_leg_id)

    ready? =
      case {expected, result} do
        {:main, {:ok, %{attachment: %{admission: :main}}}} -> true
        {:acceptance_ready, {:ok, %{transfer_acceptance_ready?: true}}} -> true
        _pending -> false
      end

    if ready? or System.monotonic_time(:millisecond) >= deadline do
      result
    else
      receive do
      after
        10 -> await_transfer_state(expected, deadline)
      end
    end
  end
end
