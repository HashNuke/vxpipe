defmodule Vxpipe.Persistence.TelephonyDefinitionCredentialsTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials, TelephonyServices}
  alias Vxpipe.Persistence.{CallStore, CredentialKeyring, CredentialStore, DefinitionStore}
  alias Vxpipe.Persistence.{ProviderCredentialStore, TelephonyServiceStore}
  alias Vxpipe.Persistence.Schema.{Call, DefinitionRevision, ParticipantRoute, ProviderCredential}

  setup do
    {:ok, keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      call_repository: {CallStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Phone definitions", [:calls], options)

    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other phone tenant", [:calls], options)
    [tenant: tenant, other: other, principal: principal, options: options, context: context]
  end

  test "a missing later phone destination is a hard save failure with no revision or route",
       data do
    assert {:error, error} = Calls.save_definition(data.tenant.key, source(), data.options)
    assert error.code == :provider_credential_unavailable
    assert error.details["path"] == ["participants", "phone", "connection", "service"]
    assert row_counts() == [0, 0, 0]
  end

  test "a same-name service in another tenant cannot authorize a save", data do
    register(data.other.key, data.options)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.save_definition(data.tenant.key, source(), data.options)

    assert row_counts() == [0, 0, 0]
  end

  test "saved and prepared phone intent requires the current active credential without persisting it",
       data do
    {credential, _service} = register(data.tenant.key, data.options)
    assert {:ok, draft} = Calls.save_definition(data.tenant.key, source(), data.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_definition(data.tenant.key, draft.definition_id, 1, data.options)

    assert [route] = published.routes
    assert {:ok, call, _token} = Calls.prepare_call(data.principal, route.key, %{}, data.options)
    refute :erlang.term_to_binary({draft, call}) =~ "private-marker"

    assert {:error, :call_id_conflict} =
             Calls.prepare_call(
               data.principal,
               route.key,
               %{},
               Keyword.put(data.options, :call_id_generator, fn -> call.id end)
             )

    revoke(credential.id)
    before = row_counts()

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.publish_definition(data.tenant.key, draft.definition_id, 1, data.options)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.prepare_call(data.principal, route.key, %{}, data.options)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.save_definition(data.tenant.key, source(), data.options)

    assert row_counts() == before
  end

  test "revocation after preflight prevents the final revision or prepared-call write", data do
    register(data.tenant.key, data.options)
    assert {:ok, draft} = Calls.save_definition(data.tenant.key, source(), data.options)

    assert {:ok, published} =
             Calls.publish_definition(data.tenant.key, draft.definition_id, 1, data.options)

    assert [route] = published.routes

    for operation <- [:save, :prepare] do
      Repo.update_all(ProviderCredential, set: [status: "active"])
      switch = start_supervised!({Agent, fn -> true end}, id: operation)

      options =
        Keyword.put(data.options, :telephony_service_repository, {
          Vxpipe.Persistence.TestRevokingTelephonyServiceRepository,
          Keyword.put(data.context, :revocation_switch, switch)
        })

      before = row_counts()

      result =
        case operation do
          :save -> Calls.save_definition(data.tenant.key, source(), options)
          :prepare -> Calls.prepare_call(data.principal, route.key, %{}, options)
        end

      assert {:error, %{code: :provider_credential_unavailable}} = result
      assert row_counts() == before
    end
  end

  test "service lookup and encryption failures authorize no write or callback", data do
    register(data.tenant.key, data.options)

    {:ok, wrong_keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})

    for keyring <- [nil, wrong_keyring] do
      context = Keyword.put(data.context, :keyring, keyring)

      options =
        Keyword.put(data.options, :telephony_service_repository, {TelephonyServiceStore, context})

      assert {:error, %{code: :provider_credential_unavailable}} =
               Calls.save_definition(data.tenant.key, source(), options)

      assert {:error, _reason} =
               TelephonyServices.with_active(
                 data.tenant.key,
                 [%{name: "support", path: ["service"]}],
                 options,
                 fn -> send(self(), :unauthorized_callback) end
               )

      refute_received :unauthorized_callback
    end

    assert row_counts() == [0, 0, 0]
  end

  test "the service guard and authorized write share a transaction and roll back together",
       data do
    register(data.tenant.key, data.options)
    before = Repo.aggregate(Vxpipe.Persistence.Schema.Tenant, :count)

    assert {:error, :controlled_write_failure} =
             TelephonyServices.with_active(
               data.tenant.key,
               [%{name: "support", path: ["service"]}],
               data.options,
               fn ->
                 assert Repo.in_transaction?()

                 {:ok, _, _} =
                   Administration.bootstrap_tenant("Rolled back", [:calls], data.options)

                 {:error, :controlled_write_failure}
               end
             )

    assert Repo.aggregate(Vxpipe.Persistence.Schema.Tenant, :count) == before
  end

  defp register(tenant, options) do
    {:ok, credential} =
      ProviderCredentials.provision(
        tenant,
        "telnyx",
        "phone",
        "api_key",
        %{"api_key" => "#{tenant}-private-marker"},
        options
      )

    {:ok, service} =
      TelephonyServices.register(
        tenant,
        %{
          "name" => "support",
          "ingress_key" => "phone-#{tenant}",
          "provider" => "telnyx",
          "provider_connection_id" => "connection-1",
          "credential_id" => credential.id,
          "public_key" => Base.encode64(:binary.copy(<<1>>, 32))
        },
        options
      )

    {credential, service}
  end

  defp revoke(id),
    do:
      Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^id),
        set: [status: "revoked"]
      )

  defp row_counts,
    do: Enum.map([DefinitionRevision, ParticipantRoute, Call], &Repo.aggregate(&1, :count))

  defp source do
    %{
      schema_version: "20260915.01",
      name: "Phone destination",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "local"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          transfers: ["phone"],
          first_message: %{mode: "wait_for_input"}
        },
        "phone" => %{
          type: "human",
          connection: %{service: "support", mode: "dial", number: "+15550001001"}
        }
      }
    }
  end
end
