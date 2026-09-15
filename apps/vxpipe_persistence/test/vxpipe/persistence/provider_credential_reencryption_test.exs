defmodule Vxpipe.Persistence.ProviderCredentialReencryptionTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CredentialCipher, CredentialKeyring, CredentialStore}
  alias Vxpipe.Persistence.ProviderCredentialStore
  alias Vxpipe.Persistence.Schema.ProviderCredential

  setup do
    {:ok, tenant, _issued} =
      Administration.bootstrap_tenant("Re-encryption tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, other, _issued} =
      Administration.bootstrap_tenant("Other re-encryption tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    keys = Map.new(["v0", "v1", "v2"], &{&1, :crypto.strong_rand_bytes(32)})
    {:ok, old} = CredentialKeyring.new("v1", Map.take(keys, ["v1"]))
    {:ok, earlier} = CredentialKeyring.new("v0", Map.take(keys, ["v0"]))
    {:ok, current} = CredentialKeyring.new("v2", keys)
    {:ok, retired} = CredentialKeyring.new("v2", Map.take(keys, ["v2"]))

    [tenant: tenant, other: other, old: old, earlier: earlier, current: current, retired: retired]
  end

  test "bounded resumable batches preserve every tenant value, identity and revoked status",
       data do
    first = provision(data.tenant.key, "google", data.old, "first-private-marker")
    revoked = provision(data.other.key, "google", data.old, "revoked-private-marker")
    earlier = provision(data.tenant.key, "deepgram", data.earlier, "earlier-private-marker")
    current = provision(data.other.key, "zenmux", data.current, "current-private-marker")
    update_row(revoked.id, status: "revoked")
    before = rows()

    assert {:ok, %{processed: 1, current_key_id: "v2", remaining_by_key: remaining}} =
             ProviderCredentialStore.reencrypt(context(data.current), 1)

    assert remaining == %{"v0" => 1, "v1" => 1}
    assert row(first.id).encryption_key_id == "v2"
    assert row(revoked.id).encryption_key_id == "v1"

    assert {:ok, final_progress} =
             ProviderCredentialStore.reencrypt(context(data.current), 2)

    assert final_progress == %{processed: 2, current_key_id: "v2", remaining_by_key: %{}}

    assert {:ok, repeated_progress} =
             ProviderCredentialStore.reencrypt(context(data.retired), 2)

    assert repeated_progress == %{processed: 0, current_key_id: "v2", remaining_by_key: %{}}

    for {metadata, secret} <- [
          {first, "first-private-marker"},
          {revoked, "revoked-private-marker"},
          {earlier, "earlier-private-marker"},
          {current, "current-private-marker"}
        ] do
      stored = row(metadata.id)
      original = Map.fetch!(before, metadata.id)
      assert preserved_fields(stored) == preserved_fields(original)
      assert stored.encryption_key_id == "v2"

      assert {:ok, %{"api_key" => ^secret}} =
               CredentialCipher.decrypt(
                 data.retired,
                 metadata,
                 stored.encryption_key_id,
                 stored.encrypted_payload
               )

      if metadata.id == current.id do
        assert stored == original
      else
        refute stored.encrypted_payload == original.encrypted_payload
      end
    end

    assert {:error, :provider_credential_revoked} =
             ProviderCredentialStore.resolve(
               context(data.retired),
               data.other.key,
               "google",
               "default"
             )

    assert {:ok, resolved} =
             ProviderCredentialStore.resolve(
               context(data.retired),
               data.tenant.key,
               "google",
               "default"
             )

    assert resolved.payload == %{"api_key" => "first-private-marker"}
  end

  test "an unreadable later row rolls back the whole batch and retry preserves plaintext", data do
    first = provision(data.tenant.key, "google", data.old, "first-private-marker")
    second = provision(data.other.key, "google", data.old, "second-private-marker")
    first_row = row(first.id)
    second_row = row(second.id)
    update_row(second.id, encrypted_payload: first_row.encrypted_payload)

    assert {:error, :provider_credential_unreadable} =
             ProviderCredentialStore.reencrypt(context(data.current), 2)

    assert row(first.id) == first_row
    assert row(second.id).encryption_key_id == "v1"
    update_row(second.id, encrypted_payload: second_row.encrypted_payload)

    assert {:ok, %{processed: 2, remaining_by_key: %{}}} =
             ProviderCredentialStore.reencrypt(context(data.current), 2)

    for {tenant, expected} <- [
          {data.tenant, "first-private-marker"},
          {data.other, "second-private-marker"}
        ] do
      assert {:ok, resolved} =
               ProviderCredentialStore.resolve(
                 context(data.retired),
                 tenant.key,
                 "google",
                 "default"
               )

      assert resolved.payload == %{"api_key" => expected}
    end
  end

  test "missing and wrong keys cannot rewrite a row, including an empty unconfigured batch",
       data do
    assert {:error, :credential_key_unavailable} =
             ProviderCredentialStore.reencrypt(context(nil), 1)

    metadata = provision(data.tenant.key, "google", data.old, "private-marker")
    before = row(metadata.id)

    assert {:error, :credential_key_unavailable} =
             ProviderCredentialStore.reencrypt(context(data.retired), 1)

    {:ok, wrong} =
      CredentialKeyring.new("v2", Map.put(data.current.keys, "v1", :crypto.strong_rand_bytes(32)))

    assert {:error, :provider_credential_unreadable} =
             ProviderCredentialStore.reencrypt(context(wrong), 1)

    assert row(metadata.id) == before
  end

  test "invalid batch sizes cannot authorize an unbounded operation", data do
    for size <- [0, -1, 501, nil, "10"] do
      assert {:error, :invalid_reencryption_batch_size} =
               ProviderCredentialStore.reencrypt(context(data.current), size)
    end
  end

  test "re-encryption exposes only safe progress and suppresses secret-bearing query events",
       data do
    metadata = provision(data.tenant.key, "google", data.old, "query-private-marker")
    ciphertext = row(metadata.id).encrypted_payload
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:vxpipe, :persistence, :repo, :query],
        &__MODULE__.observe_query/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    log =
      capture_log(fn ->
        assert {:ok, progress} = ProviderCredentialStore.reencrypt(context(data.current), 1)
        assert progress == %{processed: 1, current_key_id: "v2", remaining_by_key: %{}}
        refute inspect(progress) =~ "private-marker"
      end)

    refute_received {:credential_query, _metadata}
    refute log =~ "private-marker"
    refute log =~ inspect(ciphertext)
  end

  test "repository unavailability returns a safe error without changing a credential", data do
    metadata = provision(data.tenant.key, "google", data.old, "outage-private-marker")
    before = row(metadata.id)
    previous = Repo.get_dynamic_repo()

    try do
      Repo.put_dynamic_repo(Vxpipe.Persistence.UnavailableReencryptionRepo)

      assert {:error, :provider_credentials_unavailable} =
               ProviderCredentialStore.reencrypt(context(data.current), 1)
    after
      Repo.put_dynamic_repo(previous)
    end

    assert row(metadata.id) == before
  end

  def observe_query(_event, _measurements, metadata, owner),
    do: send(owner, {:credential_query, metadata})

  defp context(keyring), do: [repo: Repo, keyring: keyring]

  defp provision(tenant, provider, keyring, secret) do
    {:ok, metadata} =
      ProviderCredentials.provision(
        tenant,
        provider,
        "default",
        "api_key",
        %{"api_key" => secret},
        provider_credential_repository: {ProviderCredentialStore, context(keyring)}
      )

    metadata
  end

  defp row(id), do: Repo.get_by!(ProviderCredential, public_id: id)
  defp rows, do: Map.new(Repo.all(ProviderCredential), &{&1.public_id, &1})

  defp update_row(id, changes),
    do: Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^id), set: changes)

  defp preserved_fields(row),
    do:
      row |> Map.from_struct() |> Map.drop([:encrypted_payload, :encryption_key_id, :updated_at])
end
