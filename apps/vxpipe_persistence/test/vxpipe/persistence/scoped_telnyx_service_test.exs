defmodule Vxpipe.Persistence.ScopedTelnyxServiceTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    ProviderCredentials,
    TelephonyServices
  }

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    TelephonyServiceStore
  }

  setup do
    {:ok, keyring} = CredentialKeyring.new("scoped", %{"scoped" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      call_spec_repository: {CallSpecStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, first, issued} =
      Administration.bootstrap_tenant("First scoped phone", [:admin, :calls], options)

    {:ok, author} = Administration.authenticate(first.key, issued.secret, :admin, options)
    {:ok, second, _} = Administration.bootstrap_tenant("Second scoped phone", [:admin], options)
    %{first: first, second: second, author: author, context: context, options: options}
  end

  test "distinct tenant applications inherit a platform credential and tenant presence wins",
       data do
    {:ok, platform} = credential(:platform, 1, data.options)

    for tenant <- [data.first, data.second] do
      assert {:ok, service} =
               TelephonyServices.register(tenant.key, application(tenant.key), data.options)

      assert service.credential_name == "telnyx"
      assert service.credential_id == nil
      assert service.public_key == nil
      assert {:ok, snapshot} = TelephonyServices.resolve(tenant.key, "support", data.options)
      assert snapshot.credential.credential.id == platform.id
      assert snapshot.service.credential_owner == :platform
      assert snapshot.service.public_key == public_key(1)
      assert TelephonyServices.reference(snapshot.service).credential_owner == :platform
    end

    {:ok, own} = credential(data.first.key, 2, data.options)
    assert {:ok, overridden} = TelephonyServices.resolve(data.first.key, "support", data.options)
    assert overridden.service.credential_id == own.id
    assert overridden.service.credential_owner == {:tenant, data.first.key}
    assert overridden.service.public_key == public_key(2)
    reference = TelephonyServices.reference(overridden.service)
    assert :ok = ProviderCredentials.delete(data.first.key, own.id, data.options)
    assert {:ok, inherited} = TelephonyServices.resolve(data.first.key, "support", data.options)
    assert inherited.service.credential_id == platform.id

    assert {:error, {:provider_credential_unavailable, ["phone"]}} =
             TelephonyServiceStore.with_active(
               data.context,
               data.first.key,
               [%{name: "support", path: ["phone"], reference: reference}],
               fn -> flunk("changed identity reached write") end
             )
  end

  test "existing tenant credentials without a verifier do not borrow the platform key", data do
    {:ok, _platform} = credential(:platform, 1, data.options)

    assert {:ok, _service} =
             TelephonyServices.register(data.first.key, application(data.first.key), data.options)

    assert {:ok, own} =
             ProviderCredentials.provision(
               data.first.key,
               "telnyx",
               "telnyx",
               "api_key",
               %{"api_key" => "synthetic-without-verifier"},
               data.options
             )

    assert {:error, :provider_credential_unavailable} =
             TelephonyServices.resolve(data.first.key, "support", data.options)

    assert :ok = ProviderCredentials.delete(data.first.key, own.id, data.options)
    assert {:ok, restored} = TelephonyServices.resolve(data.first.key, "support", data.options)
    assert restored.service.public_key == public_key(1)
  end

  test "application lookup returns only explicit scoped mappings", data do
    {:ok, _platform} = credential(:platform, 1, data.options)
    attributes = application(data.first.key)
    {:ok, service} = TelephonyServices.register(data.first.key, attributes, data.options)

    assert {:ok, ^service} =
             TelephonyServices.fetch_telnyx_application(
               service.provider_connection_id,
               data.options
             )

    {:ok, own} = credential(data.first.key, 2, data.options)

    legacy = %{
      "name" => "legacy",
      "provider" => "telnyx",
      "ingress_key" => "legacy-ingress",
      "provider_connection_id" => "legacy-application",
      "credential_id" => own.id,
      "public_key" => public_key(2)
    }

    assert {:ok, _} = TelephonyServices.register(data.first.key, legacy, data.options)

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_application("legacy-application", data.options)
  end

  test "scoped applications cannot be assigned to two tenants or mix legacy identity fields",
       data do
    {:ok, platform} = credential(:platform, 1, data.options)
    attributes = application(data.first.key)
    assert {:ok, _} = TelephonyServices.register(data.first.key, attributes, data.options)

    other =
      application(data.second.key)
      |> Map.put("provider_connection_id", attributes["provider_connection_id"])

    assert {:error, :telephony_service_conflict} =
             TelephonyServices.register(data.second.key, other, data.options)

    for invalid <- [
          Map.put(other, "credential_id", platform.id),
          Map.put(other, "public_key", public_key(1)),
          Map.put(other, "credential_name", "alternate")
        ] do
      assert {:error, :invalid_telephony_service} =
               TelephonyServices.register(data.second.key, invalid, data.options)
    end
  end

  test "storage refuses an application that has neither an exact credential nor an effective name",
       data do
    {:ok, _} = credential(:platform, 1, data.options)

    {:ok, service} =
      TelephonyServices.register(data.first.key, application(data.first.key), data.options)

    schema = Vxpipe.Persistence.Schema.TelephonyService
    stored = Repo.get_by!(schema, public_id: service.id)
    changeset = schema.changeset(stored, %{credential_name: nil})
    assert {:error, rejected} = Repo.update(changeset, mode: :savepoint)
    assert Keyword.has_key?(rejected.errors, :credential_name)
    assert {:ok, _} = TelephonyServices.resolve(data.first.key, "support", data.options)
  end

  test "operators may author an inherited Telnyx caller but tenant edits require tenant credentials",
       data do
    {:ok, _} = credential(:platform, 1, data.options)

    assert {:ok, _} =
             TelephonyServices.register(data.first.key, application(data.first.key), data.options)

    operator = InstallationOperator.authority()

    assert {:ok, draft} =
             Calls.save_authorized_call_spec(operator, data.first.key, source(), data.options)

    update_options = Keyword.put(data.options, :call_spec_id, draft.call_spec_id)

    assert {:error, %{code: :provider_service_forbidden}} =
             Calls.save_authorized_call_spec(
               data.author,
               data.first.key,
               Map.put(source(), :name, "Tenant edit"),
               update_options
             )

    assert {:error, %{code: :provider_service_forbidden}} =
             Calls.publish_authorized_call_spec(
               data.author,
               data.first.key,
               draft.call_spec_id,
               1,
               data.options
             )

    assert {:ok, _} =
             Calls.publish_authorized_call_spec(
               operator,
               data.first.key,
               draft.call_spec_id,
               1,
               data.options
             )

    {:ok, _} = credential(data.first.key, 2, data.options)

    assert {:ok, updated} =
             Calls.save_authorized_call_spec(
               data.author,
               data.first.key,
               source(),
               update_options
             )

    assert updated.revision == 2
  end

  defp credential(owner, marker, options),
    do:
      ProviderCredentials.provision(
        owner,
        "telnyx",
        "telnyx",
        "api_key",
        %{"api_key" => "synthetic-scoped-key", "public_key" => public_key(marker)},
        options
      )

  defp public_key(marker), do: Base.encode64(:binary.copy(<<marker>>, 32))

  defp application(tenant),
    do: %{
      "name" => "support",
      "ingress_key" => "phone-#{tenant}",
      "provider" => "telnyx",
      "provider_connection_id" => "application-#{tenant}",
      "credential_name" => "telnyx"
    }

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Scoped phone caller",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "local"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "support",
            mode: "receive",
            number: "+15550001000",
            admission: "start_call"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          first_message: %{mode: "wait_for_input"}
        }
      }
    }
  end
end
