defmodule Vxpipe.Persistence.TelephonyServiceStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls.{Administration, ProviderCredentials, PublicId, TelephonyServices}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore, Repo}
  alias Vxpipe.Persistence.TelephonyServiceStore
  alias Vxpipe.Persistence.Schema.ProviderCredential

  setup do
    {:ok, tenant, _issued} =
      Administration.bootstrap_tenant("Service tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, other, _issued} =
      Administration.bootstrap_tenant("Other service tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context}
    ]

    {:ok, credential} = provision(tenant.key, "telnyx", options)
    {:ok, other_credential} = provision(other.key, "telnyx", options)

    [
      tenant: tenant,
      other: other,
      credential: credential,
      other_credential: other_credential,
      context: context,
      options: options
    ]
  end

  test "registers and reads tenant-local aliases with distinct canonical identities", data do
    assert {:ok, service} =
             TelephonyServices.register(
               data.tenant.key,
               attributes(data.credential),
               data.options
             )

    other_attributes = Map.put(attributes(data.other_credential), "ingress_key", "other-ingress")

    assert {:ok, other_service} =
             TelephonyServices.register(data.other.key, other_attributes, data.options)

    assert service.tenant_key == data.tenant.key
    assert service.name == other_service.name
    refute service.id == other_service.id
    assert service.provider == "telnyx"
    assert service.provider_connection_id == "connection-1"
    assert service.credential_id == data.credential.id
    assert service.public_key == attributes(data.credential)["public_key"]
    assert service.outbound_number == "+15551234567"
    assert service.answering_machine_detection == :detect
    assert service.media_token_ttl_ms == 60_000
    assert service.webhook_tolerance_seconds == 300
    refute Map.has_key?(Map.from_struct(service), :payload)
    refute Map.has_key?(Map.from_struct(service), :public_base_url)
    refute inspect(service) =~ "private-key-marker"

    assert {:ok, ^service} = TelephonyServices.fetch(data.tenant.key, "support", data.options)

    assert {:ok, ^other_service} =
             TelephonyServices.fetch(data.other.key, "support", data.options)

    assert {:ok, ^service} = TelephonyServices.fetch_by_ingress("support-ingress", data.options)

    assert {:ok, ^other_service} =
             TelephonyServices.fetch_by_ingress("other-ingress", data.options)

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch("AAAAAAAAAAAAAAAA", "support", data.options)

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_by_ingress("missing-ingress", data.options)
  end

  test "unique aliases and ingress keys cannot overwrite a registered binding", data do
    attributes = attributes(data.credential)
    assert {:ok, service} = TelephonyServices.register(data.tenant.key, attributes, data.options)

    assert {:error, :telephony_service_conflict} =
             TelephonyServices.register(
               data.tenant.key,
               Map.put(attributes, "ingress_key", "new-ingress"),
               data.options
             )

    assert {:error, :telephony_service_conflict} =
             TelephonyServices.register(
               data.other.key,
               attributes(data.other_credential),
               data.options
             )

    assert {:ok, ^service} = TelephonyServices.fetch(data.tenant.key, "support", data.options)

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch(data.other.key, "support", data.options)
  end

  test "resolves a private snapshot for the exact service credential and tenant", data do
    assert {:ok, service} =
             TelephonyServices.register(
               data.tenant.key,
               attributes(data.credential),
               data.options
             )

    assert {:ok, snapshot} = TelephonyServices.resolve(data.tenant.key, "support", data.options)
    assert snapshot.service == service
    assert snapshot.credential.credential.id == service.credential_id
    assert snapshot.credential.credential.tenant_key == service.tenant_key
    assert snapshot.credential.credential.provider == service.provider
    assert snapshot.credential.payload == %{"api_key" => "private-key-marker"}
    refute inspect(snapshot) =~ "private-key-marker"

    assert {:error, _reason} = TelephonyServices.resolve(data.other.key, "support", data.options)

    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^data.credential.id),
      set: [status: "revoked"]
    )

    assert {:error, _reason} = TelephonyServices.resolve(data.tenant.key, "support", data.options)
    assert {:ok, ^service} = TelephonyServices.fetch(data.tenant.key, "support", data.options)
  end

  test "registration requires a readable active credential in the same tenant and provider",
       data do
    {:ok, google} = provision(data.tenant.key, "google", data.options)

    for credential_id <- [data.other_credential.id, google.id, PublicId.uuid()] do
      attributes = Map.put(attributes(data.credential), "credential_id", credential_id)

      assert {:error, :provider_credential_unavailable} =
               TelephonyServices.register(data.tenant.key, attributes, data.options)
    end

    no_key = [telephony_service_repository: {TelephonyServiceStore, [repo: Repo, keyring: nil]}]

    assert {:error, :provider_credential_unavailable} =
             TelephonyServices.register(data.tenant.key, attributes(data.credential), no_key)

    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^data.credential.id),
      set: [status: "revoked"]
    )

    assert {:error, :provider_credential_unavailable} =
             TelephonyServices.register(
               data.tenant.key,
               attributes(data.credential),
               data.options
             )

    assert Repo.aggregate("telephony_services", :count) == 0
  end

  test "database foreign key enforces credential tenant and provider ownership", data do
    assert {:ok, service} =
             TelephonyServices.register(
               data.tenant.key,
               attributes(data.credential),
               data.options
             )

    stored = Repo.get_by!(Vxpipe.Persistence.Schema.TelephonyService, public_id: service.id)
    other = Repo.get_by!(ProviderCredential, public_id: data.other_credential.id)

    for changed <- [[tenant_id: other.tenant_id], [provider: "twilio", public_key: nil]] do
      changeset =
        stored
        |> Ecto.Changeset.change(changed)
        |> Ecto.Changeset.foreign_key_constraint(:credential_id,
          name: :telephony_services_credential_owner_fkey
        )

      assert {:error, rejected} = Repo.update(changeset, mode: :savepoint)
      assert Keyword.has_key?(rejected.errors, :credential_id)
    end

    assert {:ok, ^service} = TelephonyServices.fetch(data.tenant.key, "support", data.options)
  end

  test "rejects malformed metadata, unsupported auth fields and platform settings before storage",
       data do
    for changed <- [
          %{"provider" => "twilio"},
          %{"name" => "bad/name"},
          %{"ingress_key" => ""},
          %{"credential_id" => "not-a-uuid"},
          %{"provider_connection_id" => "connection\n1"},
          %{"public_key" => Base.encode64(<<0>>)},
          %{"outbound_number" => "not-a-number"},
          %{"answering_machine_detection" => "new-policy"},
          %{"media_token_ttl_ms" => 0},
          %{"webhook_tolerance_seconds" => -1},
          %{"api_key" => "private-key-marker"},
          %{"auth_token" => "private-key-marker"},
          %{"public_base_url" => "https://example.invalid"},
          %{"adapter" => "arbitrary-module"}
        ] do
      assert {:error, :invalid_telephony_service} =
               TelephonyServices.register(
                 data.tenant.key,
                 Map.merge(attributes(data.credential), changed),
                 data.options
               )
    end

    assert Repo.aggregate("telephony_services", :count) == 0
  end

  test "repository outage fails safely and metadata remains readable without decryption", data do
    assert {:ok, service} =
             TelephonyServices.register(
               data.tenant.key,
               attributes(data.credential),
               data.options
             )

    no_key = [telephony_service_repository: {TelephonyServiceStore, [repo: Repo, keyring: nil]}]
    assert {:ok, ^service} = TelephonyServices.fetch(data.tenant.key, "support", no_key)

    previous = Repo.get_dynamic_repo()

    try do
      Repo.put_dynamic_repo(Vxpipe.Persistence.UnavailableServiceRepo)

      assert {:error, :telephony_services_unavailable} =
               TelephonyServices.register(
                 data.tenant.key,
                 attributes(data.credential),
                 data.options
               )

      assert {:error, :telephony_services_unavailable} =
               TelephonyServices.fetch(data.tenant.key, "support", data.options)

      assert {:error, :telephony_services_unavailable} =
               TelephonyServices.fetch_by_ingress("support-ingress", data.options)

      assert {:error, :provider_credential_unavailable} =
               TelephonyServices.resolve(data.tenant.key, "support", data.options)

      assert {:error, :telephony_services_unavailable} =
               TelephonyServices.with_active(
                 data.tenant.key,
                 [%{name: "support", path: ["service"]}],
                 data.options,
                 fn -> send(self(), :unauthorized_callback) end
               )

      refute_received :unauthorized_callback
    after
      Repo.put_dynamic_repo(previous)
    end

    assert {:ok, ^service} = TelephonyServices.fetch(data.tenant.key, "support", data.options)
  end

  defp provision(tenant, provider, options) do
    ProviderCredentials.provision(
      tenant,
      provider,
      "phone-key",
      "api_key",
      %{"api_key" => "private-key-marker"},
      options
    )
  end

  defp attributes(credential) do
    %{
      "name" => "support",
      "ingress_key" => "support-ingress",
      "provider" => "telnyx",
      "provider_connection_id" => "connection-1",
      "credential_id" => credential.id,
      "public_key" => Base.encode64(:binary.copy(<<1>>, 32)),
      "outbound_number" => "+15551234567",
      "answering_machine_detection" => "detect"
    }
  end
end
