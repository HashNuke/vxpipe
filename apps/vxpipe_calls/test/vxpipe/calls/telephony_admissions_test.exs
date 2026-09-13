defmodule Vxpipe.Calls.TelephonyAdmissionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TelephonyAdmissionClaim}
  alias Vxpipe.Calls.TestMemoryRepository

  @now ~U[2026-09-11 10:10:00.000000Z]
  @started_at ~U[2026-09-11 10:10:01.000000Z]

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      definition_repository: TestMemoryRepository.definition_repository(repository),
      call_repository: TestMemoryRepository.call_repository(repository),
      registries: registries(),
      now: @now,
      actor_id_generator: fn -> "actor-phone-ingress" end,
      call_id_generator: fn -> "33333333-3333-4333-8333-333333333333" end,
      room_id_generator: fn -> "44444444-4444-4444-8444-444444444444" end
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    assert {:ok, draft} = Calls.save_definition(tenant.key, definition_input(), options)

    assert {:ok, _published} =
             Calls.publish_definition(tenant.key, draft.definition_id, 1, options)

    %{tenant: tenant, options: options}
  end

  test "atomically claims one incoming provider leg for the pinned published definition",
       context do
    event = incoming_event()

    assert {:ok,
            %TelephonyAdmissionClaim{
              call: call,
              participant_ref: "caller",
              provider_event_id: "event-incoming-1",
              provider_call_leg_id: "call-leg-1"
            } = claim} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               event,
               context.options
             )

    assert call.state == :admitting
    assert call.plan.transport == :telephony
    assert call.definition_revision == 1
    assert call.started_at == nil
    assert claim.participant_id == call.plan.participants["caller"].participant_id

    assert {:duplicate, duplicate} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               event,
               context.options
             )

    assert duplicate.call.id == call.id

    assert {:ok, stored} = Calls.fetch_call(context.tenant.key, call.id, context.options)
    assert stored.id == call.id
    assert stored.state == :admitting
  end

  test "claims a Twilio leg without inventing a separate provider session identifier", context do
    assert {:ok,
            %TelephonyAdmissionClaim{
              provider: :twilio,
              provider_connection_id: "AC00000000000000000000000000000000",
              provider_call_control_id: "CA00000000000000000000000000000000",
              provider_call_leg_id: "CA00000000000000000000000000000000",
              provider_call_session_id: nil
            }} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               twilio_incoming_event(),
               context.options
             )
  end

  test "fails closed when an event identifier and provider leg disagree", context do
    assert {:ok, _claim} =
             Calls.claim_incoming_telephony(
               :application,
               "primary-phone",
               incoming_event(),
               context.options
             )

    conflicting = %{incoming_event() | provider_call_leg_id: "call-leg-other"}

    assert {:error, :telephony_leg_conflict} =
             Calls.claim_incoming_telephony(
               :application,
               "primary-phone",
               conflicting,
               context.options
             )
  end

  test "does not claim an unpublished or mismatched destination", context do
    assert {:error, :route_unavailable} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               %{incoming_event() | to: "+15550009999"},
               context.options
             )
  end

  test "projects live room ownership onto the exact provider-leg claim", context do
    assert {:ok, claim} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               incoming_event(),
               context.options
             )

    assert {:ok, started_claim} =
             Calls.mark_incoming_telephony_started(
               claim,
               "rinc-phone-1",
               @started_at,
               context.options
             )

    assert started_claim.call.state == :running
    assert started_claim.call.incarnation_id == "rinc-phone-1"
    assert started_claim.call.started_at == @started_at

    assert {:duplicate, duplicate} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               incoming_event(),
               context.options
             )

    assert duplicate.call.state == :running
    assert duplicate.call.incarnation_id == "rinc-phone-1"
  end

  test "records a pre-live room startup failure without a start timestamp", context do
    assert {:ok, claim} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               incoming_event(),
               context.options
             )

    assert {:ok, failed_claim} =
             Calls.mark_incoming_telephony_failed(
               claim,
               :room_start_failed,
               context.options
             )

    assert failed_claim.call.state == :failed
    assert failed_claim.call.started_at == nil
    assert failed_claim.call.ended_at == @now
    assert failed_claim.call.terminal_reason == :room_start_failed
  end

  defp incoming_event do
    %Event{
      kind: :incoming,
      provider: :telnyx,
      provider_event_id: "event-incoming-1",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      occurred_at: ~U[2026-09-11 10:09:59.000000Z],
      from: "+15550001001",
      to: "+15550001000"
    }
  end

  defp twilio_incoming_event do
    %Event{
      kind: :incoming,
      provider: :twilio,
      provider_event_id: "CA00000000000000000000000000000000:incoming",
      provider_connection_id: "AC00000000000000000000000000000000",
      provider_call_control_id: "CA00000000000000000000000000000000",
      provider_call_leg_id: "CA00000000000000000000000000000000",
      provider_call_session_id: nil,
      occurred_at: ~U[2026-09-11 10:09:59.000000Z],
      from: "+15550001001",
      to: "+15550001000"
    }
  end

  defp registries do
    %{
      capability_profiles: %{
        "test-model" => %{kind: :model_inference, provider: :test, options: %{model: "test"}}
      },
      host_tools: %{}
    }
  end

  defp definition_input do
    %{
      schema_version: "20260913.01",
      name: "Inbound phone",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "primary-phone",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
