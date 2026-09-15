defmodule Vxpipe.Persistence.Integration.TelephonyAdmissionCredentialsTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Vxpipe.Persistence.TestTelephonyAdmissionFixture

  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Persistence.{CallStore, Repo, TestPausingTelephonyRepo}

  alias Vxpipe.Persistence.Schema.{
    Call,
    ProviderCredential,
    TelephonyLeg,
    TelephonyService,
    Tenant
  }

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    data = new()
    publish(data, source())

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in Tenant, where: t.key == ^data.tenant.key))
      Sandbox.checkin(Repo)
    end)

    data
  end

  test "incoming insertion retains service and credential locks until commit", data do
    worker = admission_task(data, :after)
    assert_receive {:after_inserts, ^worker}, 2_000

    mutations = [
      {TelephonyService, data.service.id, [provider_connection_id: "changed-connection"]},
      {ProviderCredential, data.credential.id, [status: "revoked"]}
    ]

    for {schema, id, changes} <- mutations do
      assert_raise Postgrex.Error, ~r/lock timeout/, fn ->
        Repo.transaction(fn ->
          Repo.query!("SET LOCAL lock_timeout = '100ms'")
          Repo.update_all(from(row in schema, where: row.public_id == ^id), set: changes)
        end)
      end
    end

    send(worker, :continue_transaction)
    assert_receive {:admission_result, ^worker, {:ok, claim}}, 2_000

    for {schema, id, changes} <- mutations do
      assert {:ok, {1, nil}} =
               Repo.transaction(fn ->
                 Repo.query!("SET LOCAL lock_timeout = '1000ms'")
                 Repo.update_all(from(row in schema, where: row.public_id == ^id), set: changes)
               end)
    end

    assert Repo.get_by!(Call, public_id: claim.call.id)
    assert tenant_count(TelephonyLeg, data.tenant.key) == 1
  end

  test "concurrent incoming duplicates recover outside the failed insert transaction", data do
    first = admission_task(data, :before)
    second = admission_task(data, :before)
    assert_receive {:before_transaction, ^first}, 2_000
    assert_receive {:before_transaction, ^second}, 2_000
    send(first, :continue_transaction)
    assert_receive {:admission_result, ^first, {:ok, original}}, 2_000
    send(second, :continue_transaction)
    assert_receive {:admission_result, ^second, {:duplicate, duplicate}}, 2_000
    assert original.call.id == duplicate.call.id
    assert tenant_count(Call, data.tenant.key) == 1
    assert tenant_count(TelephonyLeg, data.tenant.key) == 1
  end

  defp admission_task(data, phase) do
    owner = self()

    start_supervised!(
      {Task,
       fn ->
         :ok = Sandbox.checkout(Repo, sandbox: false)

         try do
           Process.put(:telephony_transaction_probe, {phase, owner})

           options =
             Keyword.put(data.options, :call_repository, {CallStore, TestPausingTelephonyRepo})

           result = incoming(data, options)
           send(owner, {:admission_result, self(), result})
         after
           Sandbox.checkin(Repo)
         end
       end},
      id: {Task, make_ref()}
    )
  end

  defp tenant_count(schema, key),
    do:
      Repo.aggregate(
        from(row in schema, join: tenant in assoc(row, :tenant), where: tenant.key == ^key),
        :count
      )
end
