defmodule Vxpipe.Persistence.Integration.ProviderCredentialReencryptionTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.{ProviderCredential, Tenant}

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    keys = Map.new(["old", "new"], &{&1, :crypto.strong_rand_bytes(32)})
    {:ok, old} = CredentialKeyring.new("old", Map.take(keys, ["old"]))
    {:ok, current} = CredentialKeyring.new("new", keys)

    {:ok, tenant, _issued} =
      Administration.bootstrap_tenant("Re-encryption transactions", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
      Sandbox.checkin(Repo)
    end)

    first = provision(tenant.key, "zulu", old)
    second = provision(tenant.key, "alpha", old)
    [tenant: tenant, first: first, second: second, current: current]
  end

  test "busy active-reader bindings remain in progress counts and can be retried", data do
    observer = self()

    reader =
      db_task(fn ->
        result =
          ProviderCredentialStore.with_active(
            context(data.current),
            data.tenant.key,
            [
              %{provider: "google", name: "alpha", path: ["alpha"]},
              %{provider: "google", name: "zulu", path: ["zulu"]}
            ],
            fn ->
              send(observer, {:credential_read_held, self()})

              receive do
                :release_read -> :ok
              after
                5_000 -> {:error, :test_read_timeout}
              end
            end
          )

        send(observer, {:credential_read_result, result})
      end)

    assert_receive {:credential_read_held, ^reader}, 1_000
    assert {:ok, progress} = ProviderCredentialStore.reencrypt(context(data.current), 2)
    assert progress == %{processed: 0, current_key_id: "new", remaining_by_key: %{"old" => 2}}
    send(reader, :release_read)
    assert_receive {:credential_read_result, :ok}, 1_000

    assert {:ok, progress} = ProviderCredentialStore.reencrypt(context(data.current), 2)
    assert progress == %{processed: 2, current_key_id: "new", remaining_by_key: %{}}
    assert_payloads(data)
  end

  test "interruption rolls back its batch while a concurrent current-key provision survives",
       data do
    observer = self()
    original = rows(data.tenant.key)

    worker =
      db_task(fn ->
        Process.put(:reencryption_test_owner, observer)

        ProviderCredentialStore.reencrypt(
          [repo: Vxpipe.Persistence.TestPausingCredentialRepo, keyring: data.current],
          2
        )
      end)

    monitor = Process.monitor(worker)
    first_id = data.first.id
    assert_receive {:reencryption_row_written, ^worker, ^first_id}, 1_000

    db_task(fn ->
      result =
        Repo.transaction(fn ->
          Repo.query!("SET LOCAL lock_timeout = '500ms'")
          provision(data.tenant.key, "concurrent", data.current)
        end)

      send(observer, {:concurrent_provision, result})
    end)

    assert_receive {:concurrent_provision, {:ok, current}}, 1_000
    assert current.encryption_key_id == "new"
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1_000

    # Acquiring these row locks acknowledges rollback/connection cleanup after the abrupt exit.
    assert {:ok, after_interrupt} =
             Repo.transaction(fn ->
               Repo.query!("SET LOCAL lock_timeout = '1000ms'")

               from(c in ProviderCredential,
                 where: c.public_id in ^[data.first.id, data.second.id],
                 lock: "FOR UPDATE"
               )
               |> Repo.all()
               |> Map.new(&{&1.public_id, &1})
             end)

    assert after_interrupt == original
    assert {:ok, progress} = ProviderCredentialStore.reencrypt(context(data.current), 2)
    assert progress == %{processed: 2, current_key_id: "new", remaining_by_key: %{}}
    assert_payloads(data)

    assert {:ok, resolved} =
             ProviderCredentialStore.resolve(
               context(data.current),
               data.tenant.key,
               "google",
               "concurrent"
             )

    assert resolved.payload == %{"api_key" => "concurrent-private-marker"}
  end

  test "a concurrent status update is skipped and retained when its credential is re-encrypted",
       data do
    observer = self()

    writer =
      db_task(fn ->
        result =
          Repo.transaction(fn ->
            Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^data.first.id),
              set: [status: "revoked"]
            )

            send(observer, {:credential_status_held, self()})

            receive do
              :commit_status -> :ok
            after
              5_000 -> Repo.rollback(:test_status_timeout)
            end
          end)

        send(observer, {:credential_status_result, result})
      end)

    assert_receive {:credential_status_held, ^writer}, 1_000
    assert {:ok, progress} = ProviderCredentialStore.reencrypt(context(data.current), 2)
    assert progress == %{processed: 1, current_key_id: "new", remaining_by_key: %{"old" => 1}}
    send(writer, :commit_status)
    assert_receive {:credential_status_result, {:ok, :ok}}, 1_000

    assert {:ok, progress} = ProviderCredentialStore.reencrypt(context(data.current), 2)
    assert progress == %{processed: 1, current_key_id: "new", remaining_by_key: %{}}
    stored = Repo.get_by!(ProviderCredential, public_id: data.first.id)
    assert stored.status == "revoked"
    assert stored.encryption_key_id == "new"

    assert {:ok, %{"api_key" => "zulu-private-marker"}} =
             Vxpipe.Persistence.CredentialCipher.decrypt(
               data.current,
               data.first,
               stored.encryption_key_id,
               stored.encrypted_payload
             )

    assert {:error, :provider_credential_revoked} =
             ProviderCredentialStore.resolve(
               context(data.current),
               data.tenant.key,
               "google",
               "zulu"
             )
  end

  defp assert_payloads(data) do
    for name <- ["alpha", "zulu"] do
      assert {:ok, resolved} =
               ProviderCredentialStore.resolve(
                 context(data.current),
                 data.tenant.key,
                 "google",
                 name
               )

      assert resolved.payload == %{"api_key" => name <> "-private-marker"}
    end
  end

  defp rows(tenant_key) do
    from(c in ProviderCredential,
      join: t in assoc(c, :tenant),
      where: t.key == ^tenant_key
    )
    |> Repo.all()
    |> Map.new(&{&1.public_id, &1})
  end

  defp provision(tenant, name, keyring) do
    {:ok, metadata} =
      ProviderCredentials.provision(
        tenant,
        "google",
        name,
        "api_key",
        %{"api_key" => name <> "-private-marker"},
        provider_credential_repository: {ProviderCredentialStore, context(keyring)}
      )

    metadata
  end

  defp context(keyring), do: [repo: Repo, keyring: keyring]

  defp db_task(operation) do
    start_supervised!(
      {Task,
       fn ->
         :ok = Sandbox.checkout(Repo, sandbox: false)

         try do
           operation.()
         after
           Sandbox.checkin(Repo)
         end
       end},
      id: {Task, make_ref()}
    )
  end
end
