defmodule Vxpipe.Persistence.ProviderCredentialStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls.{Administration, ProviderCredentials}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.ProviderCredential

  setup do
    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Provider tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, other, _issued} =
      Administration.bootstrap_tenant("Other provider tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("key-v1", %{"key-v1" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    [tenant: tenant, other: other, issued: issued, context: context, options: options(context)]
  end

  test "provisions encrypted model/speech bindings and returns only tenant metadata", data do
    for provider <- ["google", "deepgram", "zenmux"] do
      secret = provider <> "-tenant-key"

      assert {:ok, metadata} =
               ProviderCredentials.provision(
                 data.tenant.key,
                 provider,
                 "default",
                 "api_key",
                 %{"api_key" => secret},
                 data.options
               )

      assert metadata.tenant_key == data.tenant.key
      assert metadata.provider == provider
      assert metadata.name == "default"
      assert metadata.version == 1
      assert metadata.payload_schema_version == 1
      assert metadata.status == :active
      refute inspect(metadata) =~ secret
      refute Map.has_key?(Map.from_struct(metadata), :payload)

      stored = Repo.get_by!(ProviderCredential, public_id: metadata.id)
      refute stored.encrypted_payload == secret
      assert :binary.match(stored.encrypted_payload, secret) == :nomatch
      refute inspect(stored) =~ inspect(stored.encrypted_payload)
      assert stored.encryption_key_id == "key-v1"

      assert {:ok, resolved} =
               ProviderCredentials.resolve(data.tenant.key, provider, "default", data.options)

      assert resolved.credential == metadata
      assert resolved.payload == %{"api_key" => secret}
      refute inspect(resolved) =~ secret
    end

    assert {:ok, credentials} = ProviderCredentials.list(data.tenant.key, data.options)
    assert Enum.map(credentials, & &1.provider) == ["deepgram", "google", "zenmux"]
    assert {:ok, []} = ProviderCredentials.list(data.other.key, data.options)

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.resolve(data.other.key, "google", "default", data.options)

    assert {:error, :invalid_api_key} =
             Administration.authenticate(data.tenant.key, "google-tenant-key", :admin,
               credential_repository: {CredentialStore, Repo}
             )

    assert {:ok, _principal} =
             Administration.authenticate(data.tenant.key, data.issued.secret, :admin,
               credential_repository: {CredentialStore, Repo}
             )
  end

  test "rejects malformed auth and unsupported providers before persisting a binding", data do
    for {provider, kind, payload} <- [
          {"req_llm", "api_key", %{"api_key" => "secret"}},
          {"bedrock", "api_key", %{"api_key" => "secret"}},
          {"google", "oauth", %{"api_key" => "secret"}},
          {"zenmux", "oauth", %{"api_key" => "secret"}},
          {"zenmux", "api_key", %{"api_key" => "secret", "auth_token" => "mixed"}},
          {"zenmux", "api_key", %{"api_key" => " "}},
          {"zenmux", "api_key", %{"api_key" => "secret\r\nheader"}},
          {"zenmux", "api_key", %{"api_key" => String.duplicate("x", 8_193)}},
          {"telnyx", "oauth", %{"api_key" => "secret"}},
          {"telnyx", "api_key", %{"api_key" => " "}},
          {"telnyx", "api_key", %{"api_key" => "secret\r\nheader"}},
          {"telnyx", "api_key", %{"api_key" => String.duplicate("x", 4_097)}},
          {"telnyx", "api_key", %{"api_key" => "secret", "auth_token" => "mixed"}},
          {"telnyx", "api_key", %{"api_key" => "secret", "public_key" => "service-metadata"}},
          {"deepgram", "api_key", %{"api_key" => " "}},
          {"google", "api_key", %{"api_key" => "secret\r\nheader"}},
          {"google", "api_key", %{"api_key" => "secret", "auth_file" => "local.json"}},
          {"google", "api_key", %{api_key: "secret"}},
          {"google", "api_key", ["secret"]}
        ] do
      assert {:error, :invalid_provider_auth} =
               ProviderCredentials.provision(
                 data.tenant.key,
                 provider,
                 "default",
                 kind,
                 payload,
                 data.options
               )
    end

    assert {:ok, []} = ProviderCredentials.list(data.tenant.key, data.options)
  end

  test "provisions encrypted named Telnyx credentials independently for each tenant", data do
    for tenant <- [data.tenant, data.other] do
      secret = "telnyx-#{tenant.key}-private-marker"

      assert {:ok, metadata} =
               ProviderCredentials.provision(
                 tenant.key,
                 "telnyx",
                 "support-phone",
                 "api_key",
                 %{"api_key" => secret},
                 data.options
               )

      stored = Repo.get_by!(ProviderCredential, public_id: metadata.id)
      assert stored.provider == "telnyx"
      assert stored.encryption_key_id == "key-v1"
      refute stored.encrypted_payload =~ secret

      assert {:ok, resolved} =
               ProviderCredentials.resolve(tenant.key, "telnyx", "support-phone", data.options)

      assert resolved.credential == metadata
      assert resolved.payload == %{"api_key" => secret}
      assert {:ok, [^metadata]} = ProviderCredentials.list(tenant.key, data.options)
      refute inspect({metadata, resolved}) =~ "private-marker"
    end

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.resolve(data.tenant.key, "telnyx", "default", data.options)

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.resolve(data.tenant.key, "google", "support-phone", data.options)
  end

  test "enforces binding uniqueness per tenant/provider without replacing existing secrets",
       data do
    assert {:ok, first} = provision(data.tenant.key, "first", data.options)

    assert {:error, :provider_credential_conflict} =
             provision(data.tenant.key, "second", data.options)

    assert {:ok, second} = provision(data.other.key, "second", data.options)
    refute first.id == second.id

    assert {:ok, resolved} =
             ProviderCredentials.resolve(data.tenant.key, "google", "default", data.options)

    assert resolved.payload == %{"api_key" => "first"}
    assert {:error, :tenant_not_found} = provision("AAAAAAAAAAAAAAAA", "third", data.options)
  end

  test "missing keys prevent writes and fail resolution without leaking payloads", data do
    unavailable = options(Keyword.put(data.context, :keyring, nil))

    assert {:error, :credential_key_unavailable} =
             provision(data.tenant.key, "secret", unavailable)

    assert {:ok, []} = ProviderCredentials.list(data.tenant.key, data.options)
    assert {:ok, _metadata} = provision(data.tenant.key, "secret", data.options)

    assert {:error, :credential_key_unavailable} =
             ProviderCredentials.resolve(data.tenant.key, "google", "default", unavailable)

    {:ok, wrong} = CredentialKeyring.new("key-v1", %{"key-v1" => :crypto.strong_rand_bytes(32)})

    assert {:error, :provider_credential_unreadable} =
             ProviderCredentials.resolve(
               data.tenant.key,
               "google",
               "default",
               options(Keyword.put(data.context, :keyring, wrong))
             )
  end

  test "ciphertext is bound to its exact tenant, provider, binding and version", data do
    assert {:ok, first} = provision(data.tenant.key, "first", data.options)
    assert {:ok, second} = provision(data.other.key, "second", data.options)
    first_row = Repo.get_by!(ProviderCredential, public_id: first.id)

    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^second.id),
      set: [encrypted_payload: first_row.encrypted_payload]
    )

    assert {:error, :provider_credential_unreadable} =
             ProviderCredentials.resolve(data.other.key, "google", "default", data.options)

    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^first.id),
      set: [version: 2]
    )

    assert {:error, :provider_credential_unreadable} =
             ProviderCredentials.resolve(data.tenant.key, "google", "default", data.options)
  end

  test "revoked records cannot resolve even while their ciphertext and key remain available",
       data do
    assert {:ok, metadata} = provision(data.tenant.key, "secret", data.options)

    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^metadata.id),
      set: [status: "revoked"]
    )

    assert {:error, :provider_credential_revoked} =
             ProviderCredentials.resolve(data.tenant.key, "google", "default", data.options)
  end

  test "credential queries emit no SQL payload telemetry even with a subscriber installed",
       data do
    event = [:vxpipe, :persistence, :repo, :query]
    handler = "credential-query-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler, event, &__MODULE__.observe_query/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, _metadata} = provision(data.tenant.key, "secret", data.options)

    assert {:ok, _resolved} =
             ProviderCredentials.resolve(data.tenant.key, "google", "default", data.options)

    assert {:ok, [_metadata]} = ProviderCredentials.list(data.tenant.key, data.options)
    refute_received {:credential_query, _metadata}
  end

  def observe_query(_event, _measurements, metadata, owner),
    do: send(owner, {:credential_query, metadata})

  test "an unavailable repository fails safely and recovery restores credential access", data do
    assert {:ok, metadata} = provision(data.tenant.key, "before-outage", data.options)
    previous = Repo.get_dynamic_repo()
    name = Vxpipe.Persistence.CredentialRestartRepo
    repository = start_supervised!({Repo, name: name, pool_size: 1})
    monitor = Process.monitor(repository)
    stop_supervised!(Repo)
    assert_receive {:DOWN, ^monitor, :process, ^repository, :shutdown}

    try do
      for unavailable <- [name, repository] do
        Repo.put_dynamic_repo(unavailable)

        assert {:error, :provider_credentials_unavailable} =
                 provision(data.other.key, "during-outage", data.options)

        assert {:error, :provider_credentials_unavailable} =
                 ProviderCredentials.list(data.tenant.key, data.options)

        assert {:error, :provider_credentials_unavailable} =
                 ProviderCredentials.resolve(data.tenant.key, "google", "default", data.options)
      end
    after
      Repo.put_dynamic_repo(previous)
    end

    assert {:ok, [^metadata]} = ProviderCredentials.list(data.tenant.key, data.options)
    assert {:ok, []} = ProviderCredentials.list(data.other.key, data.options)

    assert {:ok, resolved} =
             ProviderCredentials.resolve(data.tenant.key, "google", "default", data.options)

    assert resolved.payload == %{"api_key" => "before-outage"}
  end

  defp provision(tenant, secret, options),
    do:
      ProviderCredentials.provision(
        tenant,
        "google",
        "default",
        "api_key",
        %{"api_key" => secret},
        options
      )

  defp options(context), do: [provider_credential_repository: {ProviderCredentialStore, context}]
end
