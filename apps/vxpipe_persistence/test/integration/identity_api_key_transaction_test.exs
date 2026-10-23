defmodule Vxpipe.Persistence.Integration.IdentityApiKeyTransactionTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Persistence.{AccessKeyStore, IdentityAccountActor, Repo}
  alias Vxpipe.Persistence.Schema.ApiKey

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    key =
      Repo.insert!(
        ApiKey.changeset(%ApiKey{}, %{
          public_id: Ecto.UUID.generate(),
          name: "Synthetic account transaction",
          scopes: ["platform"],
          digest: :crypto.strong_rand_bytes(32)
        })
      )

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(k in ApiKey, where: k.id == ^key.id))
      Sandbox.checkin(Repo)
    end)

    %{key: key}
  end

  test "account actor revalidation holds a row lock until transaction completion against revocation",
       %{key: key} do
    observer = self()
    attrs = %{actor_api_key_public_id: key.public_id}

    writer =
      start_supervised!(
        {Task,
         fn ->
           :ok = Sandbox.checkout(Repo, sandbox: false)

           result =
             Repo.transaction(fn ->
               :ok = IdentityAccountActor.revalidate(attrs, ["users.members.write"], :create)
               send(observer, {:key_locked, self()})

               receive do
                 :commit -> :written
               after
                 5_000 -> Repo.rollback(:test_timeout)
               end
             end)

           send(observer, {:writer_result, result})
           Sandbox.checkin(Repo)
         end}
      )

    monitor = Process.monitor(writer)
    assert_receive {:key_locked, ^writer}, 2_000

    assert {:error, :blocked} =
             Repo.transaction(fn ->
               Repo.query!("SET LOCAL lock_timeout = '100ms'")

               assert {:error, :repository_unavailable} =
                        AccessKeyStore.revoke(Repo, key.public_id, DateTime.utc_now())

               Repo.rollback(:blocked)
             end)

    assert Repo.get!(ApiKey, key.id).revoked_at == nil
    send(writer, :commit)
    assert_receive {:writer_result, {:ok, :written}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}, 2_000
    assert :ok = AccessKeyStore.revoke(Repo, key.public_id, DateTime.utc_now())

    assert {:ok, {:error, :forbidden}} =
             Repo.transaction(fn ->
               IdentityAccountActor.revalidate(attrs, ["users.members.write"], :create)
             end)
  end
end
