defmodule Vxpipe.Persistence.TwilioCredentialStorageTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}

  alias Vxpipe.Persistence.{
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    TelephonyServiceStore
  }

  alias Vxpipe.Persistence.Schema.{ProviderCredential, TelephonyService}

  @account "AC00000000000000000000000000000000"
  @other_account "AC11111111111111111111111111111111"
  @payload %{"account_sid" => @account, "auth_token" => "twilio-private-marker"}

  setup do
    {:ok, ring} = CredentialKeyring.new("current", %{"current" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: ring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context}
    ]

    {:ok, tenant, _} = Administration.bootstrap_tenant("Twilio credentials", [:admin], options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other Twilio tenant", [:admin], options)
    [tenant: tenant, other: other, options: options]
  end

  test "provisions private Twilio auth and resolves only its matching tenant service", data do
    for tenant <- [data.tenant, data.other] do
      assert {:ok, credential} = provision(tenant.key, @payload, data.options)
      assert credential.auth_kind == "account_sid_auth_token"

      assert {:ok, service} =
               TelephonyServices.register(
                 tenant.key,
                 attributes(tenant.key, credential.id),
                 data.options
               )

      assert service.provider_connection_id == @account
      assert service.public_key == nil
      assert {:ok, snapshot} = TelephonyServices.resolve(tenant.key, "phone", data.options)
      assert snapshot.credential.payload == @payload
      assert snapshot.credential.credential.id == credential.id
      refute inspect(snapshot) =~ "twilio-private-marker"
      stored = Repo.get_by!(ProviderCredential, public_id: credential.id)
      refute stored.encrypted_payload =~ "twilio-private-marker"
    end

    assert Repo.aggregate(TelephonyService, :count) == 2
  end

  test "rejects unsupported auth kinds and malformed or mixed payloads before writing", data do
    for payload <- [
          Map.put(@payload, "account_sid", "CA" <> String.duplicate("0", 32)),
          Map.put(@payload, "auth_token", ""),
          Map.put(@payload, "auth_token", String.duplicate("x", 4097)),
          Map.put(@payload, "auth_token", 1),
          Map.put(@payload, "auth_token", <<"invalid-token-marker", 255>>),
          Map.put(@payload, "api_key", "extra-secret"),
          Map.put(@payload, "auth_file", "unused-path")
        ] do
      assert {:error, :invalid_provider_auth} = provision(data.tenant.key, payload, data.options)
    end

    assert {:error, :invalid_provider_auth} =
             ProviderCredentials.provision(
               data.tenant.key,
               "twilio",
               "phone",
               "api_key",
               %{"api_key" => "not-twilio-auth"},
               data.options
             )

    assert Repo.aggregate(ProviderCredential, :count) == 0
  end

  test "preserves valid UTF-8 token bytes without trimming", data do
    payload = Map.put(@payload, "auth_token", "\tπ-token-marker\n")
    assert {:ok, credential} = provision(data.tenant.key, payload, data.options)

    assert {:ok, resolved} =
             ProviderCredentials.resolve(data.tenant.key, "twilio", "phone", data.options)

    assert resolved.credential.id == credential.id
    assert resolved.payload == payload
  end

  test "registration requires matching account, provider and tenant without public-key mixing",
       data do
    assert {:ok, credential} = provision(data.tenant.key, @payload, data.options)
    assert {:ok, other} = provision(data.other.key, @payload, data.options)

    assert {:ok, telnyx} =
             ProviderCredentials.provision(
               data.tenant.key,
               "telnyx",
               "phone",
               "api_key",
               %{"api_key" => "telnyx-private-marker"},
               data.options
             )

    input = attributes(data.tenant.key, credential.id)

    for changed <- [
          %{"provider_connection_id" => @other_account},
          %{"credential_id" => other.id},
          %{"credential_id" => telnyx.id}
        ] do
      assert {:error, :provider_credential_unavailable} =
               TelephonyServices.register(
                 data.tenant.key,
                 Map.merge(input, changed),
                 data.options
               )
    end

    assert {:error, :invalid_telephony_service} =
             TelephonyServices.register(
               data.tenant.key,
               Map.put(input, "public_key", Base.encode64(:binary.copy(<<1>>, 32))),
               data.options
             )

    assert Repo.aggregate(TelephonyService, :count) == 0
  end

  test "a changed account or revoked credential supplies no private authentication", data do
    assert {:ok, credential} = provision(data.tenant.key, @payload, data.options)

    assert {:ok, service} =
             TelephonyServices.register(
               data.tenant.key,
               attributes(data.tenant.key, credential.id),
               data.options
             )

    Repo.update_all(from(s in TelephonyService, where: s.public_id == ^service.id),
      set: [provider_connection_id: @other_account]
    )

    assert {:error, :provider_credential_unavailable} =
             TelephonyServices.resolve(data.tenant.key, "phone", data.options)

    Repo.update_all(from(s in TelephonyService, where: s.public_id == ^service.id),
      set: [provider_connection_id: @account]
    )

    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^credential.id),
      set: [status: "revoked"]
    )

    assert {:error, :provider_credential_unavailable} =
             TelephonyServices.resolve(data.tenant.key, "phone", data.options)

    assert {:ok, metadata} = TelephonyServices.fetch(data.tenant.key, "phone", data.options)
    assert metadata.id == service.id
  end

  defp provision(tenant, payload, options),
    do:
      ProviderCredentials.provision(
        tenant,
        "twilio",
        "phone",
        "account_sid_auth_token",
        payload,
        options
      )

  defp attributes(tenant, credential),
    do: %{
      "name" => "phone",
      "ingress_key" => "twilio-#{tenant}",
      "provider" => "twilio",
      "provider_connection_id" => @account,
      "credential_id" => credential
    }
end
