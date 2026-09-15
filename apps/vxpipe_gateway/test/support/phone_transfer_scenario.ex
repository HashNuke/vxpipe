defmodule Vxpipe.Gateway.PhoneTransferScenario do
  @moduledoc false

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Telephony.Event

  alias Vxpipe.Gateway.Telephony.{
    LegSupervisor,
    MediaAdmission,
    MediaSupervisor,
    OutgoingLegConnector,
    ServiceRegistry
  }

  @twilio_account_sid "AC00000000000000000000000000000000"
  @twilio_call_sid "CA00000000000000000000000000000001"
  @twilio_stream_sid "MZ00000000000000000000000000000001"

  def compile_plan do
    {:ok, definition} =
      CallDefinition.new(
        %{
          schema_version: CallDefinition.schema_version(),
          wait_sounds: %{call_setup: nil},
          entry_caller: "caller",
          entry_receiver: "reception",
          defaults: %{capabilities: %{}},
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
                  options: %{
                    encoding: "linear16",
                    sample_rate: 48_000
                  }
                }
              },
              tools: %{},
              transfers: ["human-support"]
            },
            "human-support" => %{
              type: "human",
              description: "A human support specialist",
              connection: %{
                service: "primary-phone",
                mode: "dial",
                number: "+15550001001"
              },
              transfer_notice: "This call is recorded."
            }
          },
          transfer_policy: %{attempt_timeout_ms: 10_000},
          limits: %{max_duration_ms: 60_000}
        },
        resource_id: "outbound-phone-transfer-definition",
        revision: 1
      )

    {:ok, invocation} =
      CallInvocation.new(
        %{
          call_definition: %{id: "outbound-phone-transfer-definition", revision: 1},
          initial_variables: %{},
          transport: %{type: "web"}
        },
        tenant_id: "tenant-outbound-phone",
        actor_id: "actor-outbound-phone",
        call_id: unique_id("call"),
        room_id: unique_id("room")
      )

    {:ok, plan} =
      DefinitionCompiler.compile(definition, invocation, %{
        host_tools: %{}
      })

    plan
  end

  def connector(provider, tenant_id, observer, leg_id, service_overrides \\ []) do
    registry =
      ServiceRegistry.init!(
        enabled: true,
        services: [service(provider, tenant_id, observer, service_overrides)]
      )

    {OutgoingLegConnector,
     [
       leg_id: fn -> leg_id end,
       leg_supervisor: LegSupervisor,
       media_admission: MediaAdmission,
       media_supervisor: MediaSupervisor,
       service_registry: registry
     ]}
  end

  def attach(plan, room, participant, connection_id, output_sink) do
    {:ok, command} =
      AttachConnection.new(
        tenant_id: plan.tenant_id,
        actor_id: plan.actor_id,
        room_id: plan.room_id,
        incarnation_id: room.incarnation_id,
        participant_id: participant.participant_id,
        connection_id: connection_id,
        deadline: future_deadline()
      )

    with {:ok, attachment} <-
           Vxpipe.CallEngine.TestTransferConnection.attach(command, output_sink) do
      Vxpipe.CallEngine.TestCallStartup.await_ready(room.room_id)
      {:ok, attachment}
    end
  end

  def send_command(plan, room, caller, content) do
    {:ok, command} =
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

  def media_started_event(:telnyx, leg_id) do
    %Event{
      kind: :media_started,
      provider: :telnyx,
      provider_call_control_id: "outbound-call-control",
      provider_connection_id: "voice-application-1",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      leg_id: leg_id,
      stream_id: "outbound-stream"
    }
  end

  def media_started_event(:twilio, leg_id) do
    %Event{
      kind: :media_started,
      provider: :twilio,
      provider_call_control_id: @twilio_call_sid,
      provider_connection_id: @twilio_account_sid,
      provider_call_leg_id: @twilio_call_sid,
      provider_call_session_id: nil,
      leg_id: leg_id,
      stream_id: @twilio_stream_sid
    }
  end

  def dtmf_event(:telnyx, leg_id, digit) do
    %Event{
      kind: :dtmf,
      provider: :telnyx,
      provider_event_id: unique_id("event"),
      provider_call_control_id: "outbound-call-control",
      provider_connection_id: "voice-application-1",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      leg_id: leg_id,
      digit: digit,
      occurred_at: DateTime.utc_now()
    }
  end

  def dtmf_event(:twilio, leg_id, digit) do
    %Event{
      kind: :dtmf,
      provider: :twilio,
      provider_event_id: unique_id("event"),
      provider_call_control_id: @twilio_call_sid,
      provider_connection_id: @twilio_account_sid,
      provider_call_leg_id: @twilio_call_sid,
      provider_call_session_id: nil,
      leg_id: leg_id,
      digit: digit,
      occurred_at: DateTime.utc_now()
    }
  end

  def answering_machine_event(:telnyx) do
    %Event{
      kind: :answering_machine,
      provider: :telnyx,
      provider_event_id: unique_id("event"),
      provider_call_control_id: "outbound-call-control",
      provider_connection_id: "voice-application-1",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      answering_machine: :machine,
      occurred_at: DateTime.utc_now()
    }
  end

  def answering_machine_event(:twilio) do
    %Event{
      kind: :answering_machine,
      provider: :twilio,
      provider_event_id: unique_id("event"),
      provider_call_control_id: @twilio_call_sid,
      provider_connection_id: @twilio_account_sid,
      provider_call_leg_id: @twilio_call_sid,
      provider_call_session_id: nil,
      answering_machine: :machine,
      occurred_at: DateTime.utc_now()
    }
  end

  def finish_private_briefing(briefing_tts) do
    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_audio(
      briefing_tts,
      :binary.copy(<<1_000::little-signed-16>>, 960)
    )

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )
  end

  def unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp service(provider, tenant_id, observer, overrides)

  defp service(:telnyx, tenant_id, observer, overrides) do
    Keyword.merge(
      [
        id: "primary-phone",
        ingress_key: "outbound_ingress",
        scope: {:tenant, tenant_id},
        provider: :telnyx,
        provider_connection_id: "voice-application-1",
        public_key: Base.encode64(:binary.copy(<<1>>, 32)),
        api_key: "observer:#{:erlang.pid_to_list(observer)}",
        outbound_number: "+15550001000",
        public_base_url: "https://voice.example.test/voice",
        adapter: Vxpipe.Gateway.TestTelephonyAdapter
      ],
      overrides
    )
  end

  defp service(:twilio, tenant_id, observer, overrides) do
    Keyword.merge(
      [
        id: "primary-phone",
        ingress_key: "outbound_ingress",
        scope: {:tenant, tenant_id},
        provider: :twilio,
        account_sid: @twilio_account_sid,
        auth_token: "observer:#{:erlang.pid_to_list(observer)}",
        outbound_number: "+15550001000",
        public_base_url: "https://voice.example.test/voice",
        adapter: Vxpipe.Gateway.TestTwilioTelephonyAdapter
      ],
      overrides
    )
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
end
