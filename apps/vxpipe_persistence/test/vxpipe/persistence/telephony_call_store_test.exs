defmodule Vxpipe.Persistence.TelephonyCallStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CallStore, CredentialStore, DefinitionStore, Repo}
  alias Vxpipe.Persistence.Schema.{Call, TelephonyLeg}

  @tenant_key "AAAAAAAAAAAAAAAA"
  @now ~U[2026-09-11 10:15:00.000000Z]
  @started_at ~U[2026-09-11 10:15:01.000000Z]

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      call_repository: {CallStore, Repo},
      tenant_key_generator: fn -> @tenant_key end,
      uuid_generator:
        sequence([
          "11111111-1111-4111-8111-111111111111",
          "22222222-2222-4222-8222-222222222222"
        ]),
      api_key_generator: fn -> "vxp_test-secret-value" end,
      registries: registries(),
      now: @now,
      actor_id_generator: fn -> "actor-phone-ingress" end,
      call_id_generator: fn -> "33333333-3333-4333-8333-333333333333" end,
      room_id_generator: fn -> "44444444-4444-4444-8444-444444444444" end
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        Vxpipe.Calls.TestTelephonyServiceRepository.repository([tenant])
      )

    assert {:ok, draft} = Calls.save_definition(tenant.key, definition_input(), options)

    assert {:ok, _published} =
             Calls.publish_definition(tenant.key, draft.definition_id, 1, options)

    %{tenant: tenant, options: options}
  end

  test "persists the call and initial provider leg atomically and deduplicates retries",
       context do
    event = incoming_event()

    assert {:ok, claim} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               event,
               context.options
             )

    assert claim.call.state == :admitting
    assert Repo.aggregate(Call, :count) == 1
    assert Repo.aggregate(TelephonyLeg, :count) == 1

    assert {:duplicate, duplicate} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               event,
               context.options
             )

    assert duplicate.call.id == claim.call.id
    assert Repo.aggregate(Call, :count) == 1
    assert Repo.aggregate(TelephonyLeg, :count) == 1
  end

  test "persists a Twilio leg without a fabricated provider session identifier", context do
    assert {:ok, claim} =
             Calls.claim_incoming_telephony(
               {:tenant, context.tenant.key},
               "primary-phone",
               twilio_incoming_event(),
               Keyword.put(
                 context.options,
                 :telephony_service_repository,
                 Vxpipe.Calls.TestTelephonyServiceRepository.repository(
                   [context.tenant],
                   "twilio"
                 )
               )
             )

    assert claim.provider_call_session_id == nil

    assert %TelephonyLeg{
             provider: "twilio",
             provider_call_session_id: nil
           } = Repo.one(TelephonyLeg)
  end

  test "rolls back a new call when an event identifier conflicts with another leg", context do
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
               Keyword.put(context.options, :call_id_generator, fn ->
                 "55555555-5555-4555-8555-555555555555"
               end)
             )

    assert Repo.aggregate(Call, :count) == 1
    assert Repo.aggregate(TelephonyLeg, :count) == 1
  end

  test "atomically projects the live incarnation onto the call and provider leg", context do
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

    assert %TelephonyLeg{state: "active", incarnation_id: "rinc-phone-1"} =
             Repo.one(TelephonyLeg)
  end

  test "atomically marks the call and initial leg terminal when room startup fails", context do
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
    assert %TelephonyLeg{state: "ended", incarnation_id: nil} = Repo.one(TelephonyLeg)
  end

  defp incoming_event do
    %Event{
      kind: :incoming,
      provider: :telnyx,
      provider_event_id: "event-incoming-1",
      provider_connection_id: "connection-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      occurred_at: ~U[2026-09-11 10:14:59.000000Z],
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
      occurred_at: ~U[2026-09-11 10:14:59.000000Z],
      from: "+15550001001",
      to: "+15550001000"
    }
  end

  defp sequence(values) do
    key = {__MODULE__, make_ref()}
    Process.put(key, values)

    fn ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  defp registries do
    %{
      host_tools: %{}
    }
  end

  defp definition_input do
    %{
      schema_version: "20260915.01",
      name: "Inbound phone",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
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
