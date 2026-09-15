defmodule Vxpipe.Persistence.TelephonyAdmissionIdentityTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query
  import Vxpipe.Persistence.TestTelephonyAdmissionFixture

  alias Vxpipe.Calls
  alias Vxpipe.Calls.TelephonyServices
  alias Vxpipe.Persistence.CallStore
  alias Vxpipe.Persistence.Schema.{Call, TelephonyLeg, TelephonyService}

  setup do
    data = new()
    publish(data, source())
    data
  end

  test "matching provider IDs and aliases remain distinct across tenant admissions and retries",
       data do
    other = new()
    publish(other, source())
    assert {:ok, first} = incoming(data, data.options)
    assert {:ok, second} = incoming(other, other.options)
    refute first.call.id == second.call.id

    for {owner, original} <- [{data, first}, {other, second}] do
      assert Map.get(original, :service_id) == owner.service.id
      assert {:duplicate, retry} = incoming(owner, owner.options)
      assert retry.call.id == original.call.id
      assert retry.call.tenant_key == owner.tenant.key

      assert {:ok, running} =
               Calls.mark_incoming_telephony_started(
                 retry,
                 "incarnation-#{owner.tenant.key}",
                 ~U[2026-09-16 00:01:00.000000Z],
                 owner.options
               )

      assert running.call.state == :running

      assert {:ok, stored} = Calls.fetch_call(owner.tenant.key, original.call.id, owner.options)
      assert stored.incarnation_id == "incarnation-#{owner.tenant.key}"
    end

    assert Repo.aggregate(Call, :count) == 2
    assert Repo.aggregate(TelephonyLeg, :count) == 2
  end

  test "a new canonical service reusing an alias does not inherit the old service's duplicate",
       data do
    assert {:ok, first} = incoming(data, data.options)

    Repo.update_all(from(s in TelephonyService, where: s.public_id == ^data.service.id),
      set: [name: "archived-support"]
    )

    assert {:ok, replacement} =
             TelephonyServices.register(
               data.tenant.key,
               %{
                 "name" => "support",
                 "ingress_key" => "replacement-#{data.tenant.key}",
                 "provider" => "telnyx",
                 "provider_connection_id" => "connection-1",
                 "credential_id" => data.credential.id,
                 "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
               },
               data.options
             )

    assert {:ok, second} = incoming(data, data.options)
    assert Map.get(first, :service_id) == data.service.id
    assert Map.get(second, :service_id) == replacement.id
    refute first.call.id == second.call.id
    assert {:duplicate, retry} = incoming(data, data.options)
    assert retry.call.id == second.call.id
    assert Repo.aggregate(Call, :count) == 2
  end

  test "incoming provider and account must match the prepared tenant service", data do
    for incoming_event <- [
          %{event() | provider: :twilio},
          %{event() | provider_connection_id: "another-account"}
        ] do
      assert {:error, :telephony_service_mismatch} =
               Calls.claim_incoming_telephony(
                 {:tenant, data.tenant.key},
                 "support",
                 incoming_event,
                 data.options
               )
    end

    assert Repo.aggregate(Call, :count) == 0
    assert Repo.aggregate(TelephonyLeg, :count) == 0
  end

  test "duplicate event and leg IDs cannot hide a different provider leg identity", data do
    assert {:ok, original} = incoming(data, data.options)

    for incoming_event <- [
          %{event() | provider_call_control_id: "other-control"},
          %{event() | provider_call_session_id: "other-session"}
        ] do
      assert {:error, :telephony_leg_conflict} =
               Calls.claim_incoming_telephony(
                 {:tenant, data.tenant.key},
                 "support",
                 incoming_event,
                 data.options
               )
    end

    assert {:duplicate, retry} = incoming(data, data.options)
    assert retry.call.id == original.call.id
    assert Repo.aggregate(Call, :count) == 1
  end

  test "a stored same-leg retry can have a different provider event ID", data do
    assert {:ok, original} = incoming(data, data.options)

    assert {:duplicate, retry} =
             Calls.claim_incoming_telephony(
               {:tenant, data.tenant.key},
               "support",
               %{event() | provider_event_id: "retry-event"},
               data.options
             )

    assert retry.call.id == original.call.id
    assert retry.provider_event_id == original.provider_event_id
  end

  test "an unbound historical event or leg is inspectable but never becomes a new admission",
       data do
    assert {:ok, original} = incoming(data, data.options)
    Repo.update_all(TelephonyLeg, set: [service_id: nil])

    assert {:ok, inspected} = Calls.fetch_call(data.tenant.key, original.call.id, data.options)
    assert inspected.plan == original.call.plan

    for incoming_event <- [
          event(),
          %{event() | provider_event_id: "retry-event"},
          %{event() | provider_call_leg_id: "different-leg"}
        ] do
      assert {:error, :legacy_telephony_claim} =
               Calls.claim_incoming_telephony(
                 {:tenant, data.tenant.key},
                 "support",
                 incoming_event,
                 data.options
               )
    end

    other = new()
    publish(other, source())
    assert {:ok, _other_call} = incoming(other, other.options)
    assert Repo.aggregate(Call, :count) == 2
    assert Repo.aggregate(TelephonyLeg, :count) == 2
  end

  test "the repository refuses a claim whose canonical identity disagrees with its pinned plan",
       data do
    assert {:ok, original} = incoming(data, data.options)

    for service_id <- [nil, Ecto.UUID.generate()] do
      forged = Map.put(original, :service_id, service_id)

      assert {:error, :telephony_service_mismatch} =
               CallStore.claim_incoming_telephony(
                 Repo,
                 forged,
                 fn -> flunk("a mismatched claim must not reach authorization") end
               )

      assert {:error, :telephony_service_mismatch} =
               Calls.mark_incoming_telephony_started(
                 forged,
                 "forged-incarnation",
                 ~U[2026-09-16 00:01:00.000000Z],
                 data.options
               )
    end

    assert Repo.get_by!(Call, public_id: original.call.id).state == :admitting
  end
end
