defmodule Vxpipe.Console.Test.SavedMCPTelephonyCase do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks
  import Vxpipe.Console.Test.SavedMCPRuntimeCase

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.Calls.{ProviderCredentials, ProviderCredentialSource, TelephonyServices}
  alias Vxpipe.CallEngine.{TestSpeechToTextTransport, TestTextToSpeechTransport}
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Console.Test.{SavedMCPLegacyAdmission, SavedMCPWireConnectionProvider}
  alias Vxpipe.Gateway.{CallAdmission, TelnyxFixture, TestTelephonyAdapter, TestTelephonySocket}
  alias Vxpipe.Gateway.CallCleanupSupervisor
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Gateway.Telephony.{CallIngress, LegSupervisor, ServiceRegistry}

  alias Vxpipe.Persistence.{
    ArchiveStore,
    EctoStorage,
    InspectionStore,
    ProviderCredentialStore,
    Repo,
    TelephonyServiceStore,
    UsageStore
  }

  alias Vxpipe.Providers.Telnyx.{ClientState, TelephonyMediaSocket}

  @received_at DateTime.to_unix(~U[2026-09-11 15:00:05Z])

  def configure(c) do
    options =
      Keyword.merge(c.options,
        provider_credential_repository: {ProviderCredentialStore, c.context},
        telephony_service_repository: {TelephonyServiceStore, c.context},
        archive_repository: {ArchiveStore, Repo},
        inspection_repository: {InspectionStore, Repo},
        usage_repository: {UsageStore, Repo}
      )

    configured = Application.get_env(:vxpipe_calls, Calls, [])
    Application.put_env(:vxpipe_calls, Calls, Keyword.merge(configured, options))
    configure_admission(options)
    configure_speech()

    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    carrier_token = "observer:#{:erlang.pid_to_list(self())}"

    assert {:ok, _} =
             ProviderCredentials.provision(
               c.tenant,
               "telnyx",
               "telnyx",
               "api_key",
               %{
                 "api_key" => carrier_token,
                 "public_key" => Base.encode64(public)
               },
               options
             )

    assert {:ok, _} =
             ProviderCredentials.provision(
               c.tenant,
               "deepgram",
               "saved-phone",
               "api_key",
               %{
                 "api_key" => "synthetic-saved-phone-speech"
               },
               options
             )

    assert {:ok, service} =
             TelephonyServices.register(
               c.tenant,
               %{
                 "name" => "saved-phone",
                 "ingress_key" => "phone-" <> c.tenant,
                 "provider" => "telnyx",
                 "provider_connection_id" => "voice-application-harness",
                 "credential_name" => "telnyx",
                 "outbound_number" => "+15550001000"
               },
               options
             )

    runtime =
      options
      |> Keyword.put(:managed_cleanup, true)
      |> Keyword.put(:archive,
        enabled: true,
        writer: {EctoStorage, options},
        maximum_pending_facts: 256,
        retry_delay_ms: 25,
        drain_timeout_ms: 5_000,
        source_policy: %{"revision" => 0, "save_transcripts" => true}
      )
      |> Keyword.put(:credential_source, {ProviderCredentialSource, options})
      |> Keyword.put(:remote_mcp_connection_provider, SavedMCPWireConnectionProvider)

    endpoint_options = [
      call_admission: [enabled: true, backend: {CallAdmission, runtime}],
      telephony: [
        enabled: true,
        public_base_url: "https://voice.example.test",
        clock: fn -> @received_at end,
        adapters: %{telnyx: TestTelephonyAdapter},
        provider_credential_repository: {ProviderCredentialStore, c.context},
        telephony_service_repository: {TelephonyServiceStore, c.context},
        handler: {CallIngress, backend: {CallAdmission, runtime}}
      ]
    ]

    endpoint_options = legacy_options(endpoint_options, Map.get(c, :legacy, false))
    Phoenix.Config.put(Endpoint, :gateway_mount, Mount.init(endpoint_options))
    endpoint = Vxpipe.Gateway.HTTP.Endpoint.init(endpoint_options)

    {:ok, configured_service} =
      ServiceRegistry.fetch(endpoint.router.telephony.registry, service.ingress_key)

    on_exit(fn -> LegSupervisor.stop(configured_service.identity, "inbound-call-leg") end)

    Map.merge(c, %{
      options: options,
      phone_endpoint: endpoint,
      phone_service: service,
      signing_key: private,
      private_values: [carrier_token, "synthetic-saved-phone-speech"]
    })
  end

  def publish(c, direction) do
    source = phone_source(c.connection.id, direction)
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source, c.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, c.options)

    published
  end

  def incoming(c, published) do
    assert post_event(c, "call-initiated-incoming").status == 200
    assert_receive {:test_telephony_answer, answer}, 5_000
    assert post_event(c, "call-answered-incoming").status == 200
    assert {:ok, page} = Calls.list_calls(c.principal, c.options)
    [call] = Enum.filter(page.calls, &(&1.call_spec_id == published.call_spec_id))
    assert {:ok, call} = Calls.fetch_call(c.tenant, call.id, c.options)
    track_cleanup(c, call)
    assert call.state == :running
    assert call.gateway_cleanup_required == not Map.get(c, :legacy, false)

    if Map.get(c, :legacy, false) do
      id = call.id
      assert_receive {:saved_mcp_legacy_started, ^id}
    end

    assert_private_absent(c, call.plan)
    open_media(c, call, answer, :incoming)
  end

  def outgoing(c, published) do
    path = "/api/tenants/#{c.tenant}/call-specs/#{published.call_spec_id}/calls"
    response = api(c.secret, :post, path, %{"to" => "+15550001002"})
    assert response.status == 201, response.resp_body
    body = JSON.decode!(response.resp_body)
    assert_private_absent(c, body)
    assert {:ok, call} = Calls.fetch_call(c.tenant, body["call"]["id"], c.options)
    track_cleanup(c, call)
    assert call.state == :running
    assert call.gateway_cleanup_required
    assert_private_absent(c, call.plan)
    assert_receive {:test_telephony_dial, dial}, 5_000
    on_exit(fn -> LegSupervisor.stop_outgoing(dial.leg_id) end)

    assert TelnyxFixture.post_event(
             c.phone_endpoint,
             c.signing_key,
             c.tenant,
             "call-initiated-outgoing",
             %{"client_state" => ClientState.encode(dial.leg_id)},
             @received_at
           ).status == 200

    open_media(c, call, dial, :outgoing)
  end

  defp open_media(c, call, command, direction) do
    prefix = if direction == :incoming, do: "inbound", else: "outbound"
    stream = prefix <> "-saved-stream"

    socket =
      start_supervised!(
        Supervisor.child_spec({TestTelephonySocket, observer: self()}, restart: :temporary)
      )

    leg_id = if direction == :incoming, do: command.leg.leg_id, else: command.leg_id

    assert {:ok, binding, _} =
             TestTelephonySocket.open(socket, TelephonyMediaSocket, fn ->
               TelnyxFixture.open_media(c.phone_endpoint, command.media_url, %{
                 "call_control_id" => prefix <> "-call-control",
                 "call_session_id" => prefix <> "-call-session",
                 "client_state" => ClientState.encode(leg_id),
                 "from" => "+15550001001",
                 "stream_id" => stream,
                 "to" => "+15550001000"
               })
             end)

    assert binding.call_id == call.id
    assert binding.incarnation_id == call.incarnation_id
    assert_receive {:test_stt_transport_started, stt, _}, 5_000
    assert_receive {:test_tts_transport_started, tts, _}, 5_000
    # Observe the actual admitted room's input gate before sending carrier audio.
    Vxpipe.CallEngine.TestCallStartup.await_open(call.plan)
    active = %{call: call, binding: binding, socket: socket, stream: stream, stt: stt, tts: tts}
    assert_audio_input(active)
    active
  end

  def model_input(c, active, sequence, text) do
    for {event, offset} <- [{"StartOfTurn", 0}, {"EndOfTurn", 1}] do
      TestSpeechToTextTransport.deliver(
        active.stt,
        JSON.encode!(%{
          type: "TurnInfo",
          event: event,
          request_id: "fixture-ready",
          sequence_id: sequence * 2 + offset + 1,
          turn_index: sequence,
          audio_window_start: 0.0,
          audio_window_end: 0.1,
          transcript: text,
          words: [],
          trigger: "eot_threshold",
          end_of_turn_confidence: 0.99
        })
      )
    end

    assert_receive {:test_agent_runtime_stream, provider, request}, 5_000
    assert_private_absent(c, request)
    assert Enum.any?(request.messages, &(&1.role == :user and &1.content == text))
    {provider, request}
  end

  def tool_result(c, active, id) do
    assert_receive {:test_agent_runtime_stream, acknowledgement, pending}, 5_000
    assert_private_absent(c, pending)
    assert pending.tools == []

    assert Enum.any?(pending.messages, fn message ->
             message.role == :tool and message.tool_call_id == id and
               JSON.decode!(message.content) == %{"invocation_id" => id, "status" => "running"}
           end)

    finish_speech(c, active, acknowledgement, "Checking records.")
    assert_receive {:test_agent_runtime_stream, provider, result}, 5_000
    assert_private_absent(c, result)
    {provider, result}
  end

  def finish_speech(c, active, provider, text) do
    reply_text(provider, text)
    tts = active.tts
    assert_receive {:test_tts_control, ^tts, speak}, 5_000
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => text}
    assert_receive {:test_tts_control, ^tts, flush}, 5_000
    assert JSON.decode!(flush) == %{"type" => "Flush"}
    speech = "phone-speech-#{System.unique_integer([:positive])}"

    TestTextToSpeechTransport.deliver_control(
      tts,
      JSON.encode!(%{
        type: "SpeechStarted",
        request_id: "fixture-ready",
        speech_id: speech
      })
    )

    reference =
      TestTextToSpeechTransport.deliver_audio_with_result(
        tts,
        :binary.copy(<<1_000::little-signed-16>>, 4_800)
      )

    assert_receive {:test_tts_audio_result, ^reference, :ok}, 5_000

    TestTextToSpeechTransport.deliver_control(
      tts,
      JSON.encode!(%{
        type: "SpeechMetadata",
        request_id: "fixture-ready",
        speech_id: speech
      })
    )

    # The 100 ms fixture utterance produces five 20 ms carrier frames.
    for _ <- 1..5 do
      await_phone_output(c, active.socket, "media", System.monotonic_time(:millisecond) + 5_000)
    end
  end

  defp await_phone_output(c, socket, event, deadline) do
    receive do
      {:test_phone_output, ^socket, payload} ->
        message = JSON.decode!(payload)
        assert_private_absent(c, message)

        if message["event"] == event do
          if event == "media",
            do: assert(byte_size(Base.decode64!(message["media"]["payload"])) > 0)

          message
        else
          await_phone_output(c, socket, event, deadline)
        end
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> flunk("Missing phone #{event}")
    end
  end

  defp assert_audio_input(active) do
    encoder = Membrane.Opus.Encoder.Native.create(16_000, 1, 2_048, -1_000, 3_001)

    assert {:ok, payload} =
             Membrane.Opus.Encoder.Native.encode_packet(
               encoder,
               :binary.copy(<<0::16>>, 320),
               320
             )

    message = %{
      event: "media",
      stream_id: active.stream,
      sequence_number: 2,
      media: %{track: "inbound", chunk: 1, timestamp: 0, payload: Base.encode64(payload)}
    }

    assert {:ok, _} =
             TestTelephonySocket.input(active.socket, {JSON.encode!(message), opcode: :text})

    stt = active.stt
    assert_receive {:test_stt_audio, ^stt, ^payload}, 5_000
  end

  defp post_event(c, name),
    do:
      TelnyxFixture.post_event(c.phone_endpoint, c.signing_key, c.tenant, name, %{}, @received_at)

  def close(c, active) do
    leg = active.binding.leg
    socket = active.socket
    leg_monitor = Process.monitor(leg)
    socket_monitor = Process.monitor(socket)

    assert {:ok, room_monitor} =
             CallEngine.monitor_room_completion(
               c.tenant,
               active.call.room_id,
               active.call.incarnation_id
             )

    cleanup = cleanup_binding(c, active.call)

    tracker_monitor =
      if active.call.gateway_cleanup_required do
        assert {:ok, tracker} = CallCleanupSupervisor.lookup(cleanup)
        Process.monitor(tracker)
      end

    assert post_hangup(c, active.binding).status == 200
    assert_receive {:DOWN, ^room_monitor, :process, _, _}, 5_000
    assert_receive {:DOWN, ^socket_monitor, :process, ^socket, _}, 5_000
    assert_receive {:DOWN, ^leg_monitor, :process, ^leg, :normal}, 5_000

    if tracker_monitor do
      assert_receive {:DOWN, ^tracker_monitor, :process, _, :normal}, 5_000
      assert {:error, :not_found} = CallCleanupSupervisor.lookup(cleanup)
    end

    stored = await_archived(c, active.call.id, System.monotonic_time(:millisecond) + 5_000)

    if tracker_monitor do
      assert %DateTime{} = stored.gateway_cleanup_completed_at
      assert %DateTime{} = stored.ended_at
      assert DateTime.compare(stored.gateway_cleanup_completed_at, stored.ended_at) != :lt
    end

    close_admitted_call(c, active.call)
  end

  defp await_archived(c, id, deadline) do
    assert {:ok, stored} = Calls.fetch_call(c.tenant, id, c.options)
    assert {:ok, facts} = ArchiveStore.fetch_call_facts(Repo, c.tenant, id)
    assert_private_absent(c, facts)

    if stored.state == :ended and Enum.any?(facts, &(&1.kind == :archive_stream_closed)) do
      stored
    else
      assert System.monotonic_time(:millisecond) < deadline, "phone call archive did not close"

      receive do
      after
        5 -> await_archived(c, id, deadline)
      end
    end
  end

  defp track_cleanup(c, call) do
    binding = cleanup_binding(c, call)

    on_exit(fn ->
      try do
        close_admitted_call(c, call)
      after
        case CallCleanupSupervisor.lookup(binding) do
          {:ok, tracker} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
          {:error, :not_found} -> :ok
        end
      end
    end)
  end

  defp cleanup_binding(c, call),
    do: %{
      tenant_key: c.tenant,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: call.incarnation_id
    }

  defp post_hangup(c, binding) do
    body =
      JSON.encode!(%{
        data: %{
          record_type: "event",
          event_type: "call.hangup",
          id: "ended-" <> binding.client_state_leg_id,
          occurred_at: "2026-09-11T15:00:04.123456Z",
          payload: %{
            connection_id: binding.provider_connection_id,
            call_control_id: binding.provider_call_control_id,
            call_leg_id: binding.provider_call_leg_id,
            call_session_id: binding.provider_call_session_id,
            hangup_cause: "normal_clearing"
          }
        }
      })

    timestamp = Integer.to_string(@received_at)

    Plug.Test.conn(:post, "/webhooks/tenants/#{c.tenant}/telnyx", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("telnyx-timestamp", timestamp)
    |> Plug.Conn.put_req_header(
      "telnyx-signature-ed25519",
      TelnyxFixture.signature(body, c.signing_key, timestamp)
    )
    |> Vxpipe.Gateway.HTTP.Endpoint.call(c.phone_endpoint)
  end

  defp legacy_options(options, false), do: options

  defp legacy_options(options, true) do
    endpoint = Vxpipe.Gateway.HTTP.Endpoint.init(options)
    {CallIngress, handler} = endpoint.router.telephony.handler
    {CallAdmission, configured} = Keyword.fetch!(handler, :backend)

    configured =
      configured |> Keyword.delete(:managed_cleanup) |> Keyword.put(:legacy_observer, self())

    Keyword.update!(options, :telephony, fn telephony ->
      Keyword.put(
        telephony,
        :handler,
        {CallIngress, backend: {SavedMCPLegacyAdmission, configured}}
      )
    end)
  end

  defp configure_speech do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:speech_to_text,
        providers: %{
          Vxpipe.Providers.Deepgram.STTSession => [
            enabled: true,
            wire_module: TestSpeechToTextTransport,
            wire_options: [observer: self(), ready_on_start: true],
            media_ingress: [
              maximum_frames: 8,
              maximum_bytes: 1_024,
              maximum_age_ms: 1_000,
              maximum_consecutive_overflows: 2
            ]
          ]
        }
      )
      |> Keyword.put(:text_to_speech,
        providers: %{
          Vxpipe.Providers.Deepgram.TTSSession => [
            enabled: true,
            wire_module: TestTextToSpeechTransport,
            wire_options: [observer: self(), ready_on_start: true],
            maximum_requests: 2
          ]
        }
      )
    )
  end

  defp phone_source(id, direction) do
    original = source(id)
    connection = %{service: "saved-phone", number: "+15550001000"}

    connection =
      if direction == :incoming,
        do: Map.merge(connection, %{mode: "receive", admission: "start_call"}),
        else: connection |> Map.delete(:number) |> Map.put(:mode, "dial")

    caller = %{
      type: "human",
      connection: connection,
      capabilities: %{
        speech_to_text: %{
          provider: "deepgram",
          model: "flux-general-multi",
          credential_name: "saved-phone",
          options: %{encoding: "opus", sample_rate: 16_000}
        }
      }
    }

    assistant =
      put_in(original.participants["assistant"].capabilities[:text_to_speech], %{
        provider: "deepgram",
        model: "flux-test-voice",
        credential_name: "saved-phone",
        options: %{encoding: "linear16", sample_rate: 48_000}
      })

    source = %{
      schema_version: "20261004.01",
      defaults: %{capabilities: %{}},
      wait_sounds: nil,
      participants: Map.put(assistant.participants, "caller", caller),
      limits: %{max_duration_ms: 60_000}
    }

    if direction == :incoming,
      do: Map.put(source, :incoming_call, %{caller: "caller", handled_by: "assistant"}),
      else:
        Map.put(source, :outgoing_call, %{
          callee: "caller",
          handled_by: "assistant",
          ring_timeout_ms: 15_000
        })
  end
end
