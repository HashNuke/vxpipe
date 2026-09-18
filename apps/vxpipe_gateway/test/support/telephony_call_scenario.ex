defmodule Vxpipe.Gateway.TelephonyCallScenario do
  @moduledoc false

  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}
  alias Vxpipe.Calls.{PreparedCall, TelephonyAdmissionClaim}

  alias Vxpipe.Gateway.Telephony.{
    LegSupervisor,
    MediaSupervisor,
    OutgoingLegConnector
  }

  @twilio_account_sid "AC00000000000000000000000000000000"
  @twilio_inbound_call_sid "CA00000000000000000000000000000000"

  def build(
        provider,
        observer,
        credential,
        media_admission,
        inbound_leg_id,
        outbound_leg_id,
        options \\ []
      )
      when provider in [:telnyx, :twilio] and is_pid(observer) do
    plan = compile_plan(provider, options)
    service_options = service_options(provider, plan.tenant_id, credential, observer)
    plan = Vxpipe.Gateway.TestTelephonyServiceRepository.pin_plan(plan, service_options)
    caller = Map.fetch!(plan.participants, "caller")

    registry =
      Vxpipe.Gateway.TestTelephonyServiceRepository.registry(
        enabled: true,
        services: [service_options]
      )

    connector =
      {OutgoingLegConnector,
       [
         leg_id: fn -> outbound_leg_id end,
         leg_supervisor: LegSupervisor,
         media_admission: media_admission,
         media_supervisor: MediaSupervisor,
         service_registry: registry
       ]}

    runtime_options =
      [
        media_admission: media_admission,
        outbound_leg_connector: connector,
        service_registry: registry,
        telephony_leg_id: fn -> inbound_leg_id end,
        telephony_media_supervisor: MediaSupervisor
      ] ++ Keyword.take(options, [:recording])

    %{
      claim: claim(provider, plan, caller.participant_id),
      plan: plan,
      runtime_options: runtime_options,
      service_options: service_options
    }
  end

  defp compile_plan(provider, options) do
    id = System.unique_integer([:positive, :monotonic])

    {:ok, call_spec} =
      CallSpec.new(
        %{
          schema_version: CallSpec.schema_version(),
          entry_caller: "caller",
          entry_receiver: "reception",
          defaults: %{capabilities: %{}},
          wait_sounds: Keyword.get(options, :wait_sounds, %{}),
          participants: %{
            "caller" => %{
              type: "human",
              capabilities: %{speech_to_text: speech_selection(provider)},
              connection: %{
                service: "primary-phone",
                mode: "receive",
                admission: "start_call",
                number: "+15550001000"
              }
            },
            "reception" => %{
              type: "agent",
              prompt: "Route callers safely.",
              first_message: %{mode: "wait_for_input"},
              capabilities: %{
                model_inference: %{
                  provider: "fixture",
                  model: Keyword.get(options, :model, "test:scripted")
                },
                text_to_speech: %{
                  provider: "deepgram",
                  model: "flux-test-voice",
                  options: %{encoding: "linear16", sample_rate: 48_000}
                }
              },
              tools: %{},
              transfers: ["human-support"]
            },
            "human-support" => %{
              type: "human",
              description: "A human support specialist",
              capabilities:
                if(Keyword.get(options, :support_speech_to_text?, false),
                  do: %{speech_to_text: speech_selection(provider)},
                  else: %{}
                ),
              connection: %{
                service: "primary-phone",
                mode: "dial",
                number: "+15550001002"
              },
              transfer_notice: "This call is recorded."
            }
          },
          transfer_policy: %{attempt_timeout_ms: 10_000},
          limits: %{max_duration_ms: 60_000}
        },
        resource_id: "telephony-harness-call-spec",
        revision: 1
      )

    {:ok, invocation} =
      CallInvocation.new(
        %{
          call_spec: %{id: "telephony-harness-call-spec", revision: 1},
          initial_variables: %{},
          transport: %{type: "telephony"}
        },
        tenant_id: "telephonyharness",
        actor_id: "actor-telephony-harness",
        call_id: "call-telephony-harness-#{id}",
        room_id: "room-telephony-harness-#{id}"
      )

    {:ok, plan} =
      CallSpecCompiler.compile(call_spec, invocation, %{
        host_tools: %{}
      })

    plan
  end

  defp speech_selection(:telnyx),
    do: %{
      provider: "deepgram",
      model: "flux-general-multi",
      options: %{encoding: "opus", sample_rate: 16_000}
    }

  defp speech_selection(:twilio),
    do: %{
      provider: "deepgram",
      model: "flux-general-multi",
      options: %{encoding: "linear16", sample_rate: 8_000}
    }

  defp claim(provider, plan, participant_id) do
    identity = claim_identity(provider)

    call = %PreparedCall{
      id: plan.call_id,
      tenant_key: plan.tenant_id,
      call_spec_id: plan.call_spec_id,
      call_spec_revision: plan.call_spec_revision,
      schema_version: plan.schema_version,
      participant_routes: %{},
      entry_caller: plan.entry_caller,
      entry_receiver: plan.entry_receiver,
      initial_variables: %{},
      plan: plan,
      plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
      state: :admitting,
      room_id: plan.room_id,
      created_at: ~U[2026-09-11 15:00:00Z],
      started_at: nil,
      ended_at: nil,
      incarnation_id: nil,
      terminal_reason: nil
    }

    struct!(
      TelephonyAdmissionClaim,
      Map.merge(identity, %{
        accepted_at: ~U[2026-09-11 15:00:00Z],
        call: call,
        participant_id: participant_id,
        participant_ref: "caller",
        service: "primary-phone",
        service_id: Map.fetch!(plan.participants, "caller").telephony_service.service_id
      })
    )
  end

  defp claim_identity(:telnyx) do
    %{
      provider: :telnyx,
      provider_event_id: "event-incoming-harness",
      provider_connection_id: "voice-application-harness",
      provider_call_control_id: "inbound-call-control",
      provider_call_leg_id: "inbound-call-leg",
      provider_call_session_id: "inbound-call-session"
    }
  end

  defp claim_identity(:twilio) do
    %{
      provider: :twilio,
      provider_event_id: "#{@twilio_inbound_call_sid}:incoming",
      provider_connection_id: @twilio_account_sid,
      provider_call_control_id: @twilio_inbound_call_sid,
      provider_call_leg_id: @twilio_inbound_call_sid,
      provider_call_session_id: nil
    }
  end

  defp service_options(:telnyx, tenant_id, public_key, observer) do
    [
      id: "primary-phone",
      ingress_key: "harness",
      scope: {:tenant, tenant_id},
      provider: :telnyx,
      provider_connection_id: "voice-application-harness",
      public_key: Base.encode64(public_key),
      api_key: "observer:#{:erlang.pid_to_list(observer)}",
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test",
      adapter: Vxpipe.Gateway.TestTelephonyAdapter
    ]
  end

  defp service_options(:twilio, tenant_id, auth_token, _observer) do
    [
      id: "primary-phone",
      ingress_key: "harness",
      scope: {:tenant, tenant_id},
      provider: :twilio,
      account_sid: @twilio_account_sid,
      auth_token: auth_token,
      outbound_number: "+15550001000",
      public_base_url: "https://voice.example.test",
      adapter: Vxpipe.Gateway.TestTwilioTelephonyAdapter
    ]
  end
end
