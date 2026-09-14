defmodule Vxpipe.Gateway.Telephony.TwilioCallHarnessTest do
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

  alias Vxpipe.Gateway.Telephony.Twilio.MediaSocket

  alias Vxpipe.Gateway.{
    TelephonyHarnessBackend,
    TwilioCallScenario,
    TwilioFixture
  }

  @account_sid "AC00000000000000000000000000000000"
  @incoming_call_sid "CA00000000000000000000000000000000"
  @outgoing_call_sid "CA00000000000000000000000000000001"
  @incoming_leg_id "leg-inbound-twilio-harness"
  @outgoing_leg_id "leg-outbound-twilio-harness"
  @incoming_stream_sid "MZ00000000000000000000000000000000"
  @outgoing_stream_sid "MZ00000000000000000000000000000001"
  @received_at DateTime.to_unix(~U[2026-09-11 17:00:05Z])

  setup context do
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

    admission = start_supervised!({MediaAdmission, name: nil})

    scenario_options =
      if outcome = context[:initial_outcome] do
        configured = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

        Application.put_env(
          :vxpipe_call_engine,
          Vxpipe.CallEngine.Application,
          Keyword.put(configured, :call_lifecycle,
            readiness_timeout_ms: 30_000,
            idle_timeout_ms: 15_000,
            timer: {Vxpipe.CallEngine.TestCallLifecycleTimer, observer: self()}
          )
        )

        [
          model: if(outcome == :model, do: "test:blocked-unavailable", else: "test:blocked"),
          wait_sounds: if(outcome in [:max_duration, :disconnected], do: nil, else: %{})
        ]
      else
        if mode = context[:transfer_wait_mode],
          do: Vxpipe.Gateway.PhoneHandoffAssertions.scenario_options(mode),
          else: []
      end

    scenario =
      TwilioCallScenario.build(
        self(),
        admission,
        @incoming_leg_id,
        @outgoing_leg_id,
        scenario_options
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
      LegSupervisor.stop(:twilio, "primary-phone", @incoming_call_sid)
      LegSupervisor.stop_outgoing(@outgoing_leg_id)
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    %{
      backend: backend,
      endpoint: endpoint,
      plan: scenario.plan,
      service_options: scenario.service_options
    }
  end

  for outcome <- [:ready, :model, :readiness, :max_duration, :disconnected] do
    @tag initial_outcome: outcome
    test "initial phone startup handles #{outcome} under its original clocks", context do
      outcome = context.initial_outcome
      assert post_voice(context).status == 200
      assert_receive {:test_twilio_answer, answer}, 2_000
      assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000
      preparation_monitor = Process.monitor(preparer)

      [{authority, _}] =
        Registry.lookup(
          Vxpipe.CallEngine.RoomRegistry,
          {context.plan.tenant_id, context.plan.room_id}
        )

      room_monitor = Process.monitor(authority)

      transport =
        start_supervised!(
          Supervisor.child_spec({TestTelephonySocket, observer: self()}, restart: :temporary),
          id: :initial_phone_socket
        )

      transport_monitor = Process.monitor(transport)

      assert {:ok, _binding, _socket} =
               TestTelephonySocket.open(transport, MediaSocket, fn ->
                 TwilioFixture.open_media(
                   context.endpoint,
                   context.service_options,
                   answer.media_url,
                   @incoming_call_sid,
                   @incoming_stream_sid
                 )
               end)

      if outcome in [:max_duration, :disconnected] do
        refute_receive {:test_phone_output, ^transport, _}, 150
      else
        assert_phone_wait(transport, System.monotonic_time(:millisecond) + 2_000)
      end

      assert Vxpipe.CallEngine.RoomAuthority.input_admission(
               context.plan.tenant_id,
               context.plan.room_id
             ) == :opening_audio

      refute_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
      refute_receive {:test_call_lifecycle_timer_scheduled, _, 15_000}

      case outcome do
        :ready ->
          send(preparer, :release_test_agent_runtime_model)
          assert_receive {:test_tts_transport_started, voice, _}, 2_000
          assert_receive {:test_stt_transport_started, speech, _}, 2_000

          TestTextToSpeechTransport.deliver_control(
            voice,
            ~s({"type":"Connected","request_id":"phone-voice-ready"})
          )

          assert_phone_wait(transport, System.monotonic_time(:millisecond) + 2_000)
          refute_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}

          TestSpeechToTextTransport.deliver(
            speech,
            ~s({"type":"Connected","request_id":"phone-speech-ready","sequence_id":0})
          )

          Vxpipe.CallEngine.TestCallStartup.await_open(context.plan)
          assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}, 2_000
          refute_receive {:test_call_lifecycle_timer_cancelled, ^maximum_timer}
          refute_receive {:test_tts_transport_started, _, _}
          refute_receive {:test_stt_transport_started, _, _}
          assert_caller_audio(speech, transport)

        :model ->
          send(preparer, :release_test_agent_runtime_model)

        :readiness ->
          Vxpipe.CallEngine.TestCallLifecycleTimer.fire(readiness_timer)

        :max_duration ->
          Vxpipe.CallEngine.TestCallLifecycleTimer.fire(maximum_timer)

        :disconnected ->
          stop_supervised!(:initial_phone_socket)
      end

      if outcome != :ready do
        assert_receive {:DOWN, ^room_monitor, :process, ^authority, _}, 2_000
        assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 2_000
        assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _}, 2_000
        assert_receive {:test_twilio_end_leg, request}, 2_000
        assert request.leg.leg_id == @incoming_leg_id
        assert request.reason == :room_ended
        refute_receive {:test_twilio_end_leg, _duplicate}
        refute_receive {:test_tts_transport_started, _, _}
        refute_receive {:test_call_lifecycle_timer_scheduled, _, 15_000}
      end
    end
  end

  for outcome <- [:model, :readiness, :max_duration] do
    @tag initial_outcome: outcome
    test "initial phone #{outcome} ends the answered leg before a media socket connects",
         context do
      assert post_voice(context).status == 200
      assert_receive {:test_twilio_answer, _answer}, 2_000

      [{leg, _}] =
        Registry.lookup(
          Vxpipe.Gateway.Telephony.LegRegistry,
          {:twilio, "primary-phone", @incoming_call_sid}
        )

      monitor = Process.monitor(leg)
      assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000
      preparation_monitor = Process.monitor(preparer)

      case unquote(outcome) do
        :model -> send(preparer, :release_test_agent_runtime_model)
        :readiness -> Vxpipe.CallEngine.TestCallLifecycleTimer.fire(readiness_timer)
        :max_duration -> Vxpipe.CallEngine.TestCallLifecycleTimer.fire(maximum_timer)
      end

      assert_receive {:test_twilio_end_leg, request}, 2_000
      assert request.leg.leg_id == @incoming_leg_id
      assert request.reason == :room_ended
      assert_receive {:DOWN, ^monitor, :process, ^leg, _}, 2_000
      assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 2_000
      refute_receive {:test_twilio_end_leg, _duplicate}
      refute_receive {:test_tts_transport_started, _, _}
    end
  end

  defp assert_phone_wait(transport, deadline) do
    receive do
      {:test_phone_output, ^transport, output} ->
        case JSON.decode!(output) do
          %{"event" => "media", "media" => %{"payload" => payload}} ->
            assert byte_size(Base.decode64!(payload)) > 0

          _control ->
            assert_phone_wait(transport, deadline)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("missing phone setup waiting")
    end
  end

  for {mode, loss} <- [
        {:defaults, nil},
        {:custom_url, nil},
        {:silent_all, nil},
        {:custom_url, :destination},
        {:silent_all, :cue}
      ] do
    @tag transfer_wait_mode: mode, phone_loss: loss
    test "runs one signed incoming call through private press-1 phone transfer after storage loss with #{mode} waits #{loss || :ready}",
         context do
      incoming = post_voice(context)
      assert incoming.status == 200

      assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      assert_receive {:test_twilio_answer, answer}, 2_000
      refute_receive {:test_twilio_answer, _duplicate}

      duplicate = post_voice(context)
      assert duplicate.status == 200
      refute_receive {:test_twilio_answer, _duplicate}

      :ok = TelephonyHarnessBackend.make_storage_unavailable(context.backend)

      inbound_transport =
        start_supervised!({TestTelephonySocket, observer: self()}, id: :incoming_socket)

      outbound_transport =
        start_supervised!({TestTelephonySocket, observer: self()}, id: :outgoing_socket)

      assert {:ok, inbound_binding, inbound_socket} =
               TestTelephonySocket.open(inbound_transport, MediaSocket, fn ->
                 TwilioFixture.open_media(
                   context.endpoint,
                   context.service_options,
                   answer.media_url,
                   @incoming_call_sid,
                   @incoming_stream_sid
                 )
               end)

      assert inbound_binding.client_state_leg_id == @incoming_leg_id

      assert {:ok, %{attachment: %{admission: :main}}} =
               MediaSupervisor.snapshot(@incoming_leg_id)

      assert_receive {:test_stt_transport_started, stt_transport, _connection}, 2_000

      begin_transfer(stt_transport, inbound_transport, context.plan)

      assert_receive {:test_twilio_dial, dial}, 2_000
      assert dial.leg_id == @outgoing_leg_id
      assert dial.to == "+15550001002"

      assert {:ok, _outbound_binding, _outbound_socket} =
               TestTelephonySocket.open(outbound_transport, MediaSocket, fn ->
                 TwilioFixture.open_media(
                   context.endpoint,
                   context.service_options,
                   dial.media_url,
                   @outgoing_call_sid,
                   @outgoing_stream_sid
                 )
               end)

      assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

      assert {:ok, _outbound_socket} =
               TestTelephonySocket.input(
                 outbound_transport,
                 TwilioFixture.dtmf(@outgoing_stream_sid, 2, "1")
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
                 TwilioFixture.dtmf(@outgoing_stream_sid, 100, "1")
               )

      assert_receive {:test_stt_transport_started, support_stt, _}, 2_000

      proof =
        Vxpipe.Gateway.PhoneHandoffAssertions.gate(
          :twilio,
          context.plan,
          {context.transfer_wait_mode, context.phone_loss},
          inbound_transport,
          outbound_transport,
          stt_transport,
          support_stt,
          {@incoming_leg_id, @outgoing_leg_id}
        )

      if context.phone_loss do
        Vxpipe.Gateway.PhoneHandoffAssertions.recovery(proof, source_tts)
        refute_receive {:DOWN, ^source_monitor, :process, ^source_agent, _}, 0
      else
        assert_receive {:DOWN, ^source_monitor, :process, ^source_agent, _reason}, 2_000
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
        Vxpipe.Gateway.PhoneHandoffAssertions.conversation(proof)
      end

      assert inbound_socket.stream_id == @incoming_stream_sid

      claim_count =
        Enum.count(TelephonyHarnessBackend.operations(context.backend), fn
          {:claim_incoming, _event_id} -> true
          _operation -> false
        end)

      assert claim_count == 1
    end
  end

  defp post_voice(context) do
    TwilioFixture.post_voice(
      context.endpoint,
      context.service_options,
      TwilioFixture.incoming_parameters(@account_sid, @incoming_call_sid)
    )
  end

  defp begin_transfer(stt_transport, socket, plan) do
    TestSpeechToTextTransport.deliver(
      stt_transport,
      ~s({"type":"Connected","request_id":"request-twilio-harness","sequence_id":0})
    )

    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
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
    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, _}, 2_000
    assert {:ok, acknowledgement} = ModelResponse.new(text: "Connecting support.")
    send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, acknowledgement}})
  end

  defp assert_caller_audio(stt_transport, socket) do
    message = %{
      "event" => "media",
      "streamSid" => @incoming_stream_sid,
      "sequenceNumber" => "2",
      "media" => %{
        "track" => "inbound",
        "chunk" => "1",
        "timestamp" => "0",
        "payload" => Base.encode64(:binary.copy(<<255>>, 160))
      }
    }

    assert {:ok, _socket} =
             TestTelephonySocket.input(socket, {JSON.encode!(message), opcode: :text})

    pcm = :binary.copy(<<0::16>>, 160)
    assert_receive {:test_stt_audio, ^stt_transport, ^pcm}, 2_000
  end

  defp turn_message(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-twilio-harness",
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
