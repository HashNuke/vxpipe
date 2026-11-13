defmodule Vxpipe.Persistence.SharedTelnyxRoutingTest do
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

  test "shared application routing selects the published tenant by called number", data do
    {:ok, _} = credential(:platform, 1, data.options)
    :ok = TelephonyServices.configure_platform_application("shared-app", data.options)

    for {tenant, number} <- [{data.first, "+15550001000"}, {data.second, "+15550002000"}] do
      {:ok, service} =
        TelephonyServices.register(
          tenant.key,
          Map.put(application(tenant.key), "provider_connection_id", nil),
          data.options
        )

      publish(data, tenant.key, number)

      assert {:ok, selected} =
               TelephonyServices.fetch_telnyx_route(:platform, "shared-app", number, data.options)

      assert selected.id == service.id
      assert selected.tenant_key == tenant.key
      assert selected.name == "support"
      assert selected.credential_id == nil
      assert selected.public_key == nil

      assert {:ok, ^selected} =
               TelephonyServices.fetch_telnyx_route(
                 {:tenant, tenant.key},
                 "shared-app",
                 number,
                 data.options
               )
    end

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_route(
               {:tenant, data.first.key},
               "shared-app",
               "+15550002000",
               data.options
             )

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_route(
               :platform,
               "shared-app",
               "+15550009999",
               data.options
             )

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_route(
               :platform,
               "different-app",
               "+15550001000",
               data.options
             )
  end

  test "dedicated applications still use published routes and reject ambiguous data", data do
    {:ok, _} = credential(:platform, 1, data.options)

    {:ok, _} =
      TelephonyServices.register(data.first.key, application(data.first.key), data.options)

    app = "application-#{data.first.key}"

    {:ok, draft} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.first.key,
        source(),
        data.options
      )

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_route(
               :platform,
               app,
               "+15550001000",
               data.options
             )

    force_publish(draft)

    assert {:ok, selected} =
             TelephonyServices.fetch_telnyx_route(:platform, app, "+15550001000", data.options)

    assert selected.tenant_key == data.first.key

    {:ok, duplicate} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.first.key,
        source(),
        data.options
      )

    force_publish(duplicate)

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_route(
               :platform,
               app,
               "+15550001000",
               data.options
             )
  end

  test "publishing rejects another tenant's number on the shared application", data do
    {:ok, _} = credential(:platform, 1, data.options)
    :ok = TelephonyServices.configure_platform_application("shared-app", data.options)

    for tenant <- [data.first, data.second] do
      {:ok, _} =
        TelephonyServices.register(
          tenant.key,
          Map.put(application(tenant.key), "provider_connection_id", nil),
          data.options
        )
    end

    publish(data, data.first.key, "+15550001000")

    {:ok, draft} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        data.second.key,
        source(),
        data.options
      )

    assert {:error, :phone_number_in_use} =
             Calls.publish_authorized_call_spec(
               InstallationOperator.authority(),
               data.second.key,
               draft.call_spec_id,
               draft.revision,
               data.options
             )
  end

  test "resetting an application rejects a published shared-number conflict", data do
    {:ok, _} = credential(:platform, 1, data.options)
    :ok = TelephonyServices.configure_platform_application("shared-app", data.options)

    {:ok, _} =
      TelephonyServices.register(
        data.first.key,
        Map.put(application(data.first.key), "provider_connection_id", nil),
        data.options
      )

    {:ok, second} =
      TelephonyServices.register(data.second.key, application(data.second.key), data.options)

    publish(data, data.first.key, "+15550001000")
    publish(data, data.second.key, "+15550001000")

    assert {:error, :phone_number_in_use} =
             TelephonyServiceStore.update_application(
               data.context,
               data.second.key,
               second.id,
               %{"provider_connection_id" => nil}
             )

    assert {:ok, unchanged} = TelephonyServices.fetch(data.second.key, "support", data.options)
    assert unchanged.provider_connection_id == second.provider_connection_id
  end

  test "platform and dedicated application IDs cannot overlap in either write direction", data do
    {:ok, _} = credential(:platform, 1, data.options)
    :ok = TelephonyServices.configure_platform_application("shared-app", data.options)

    assert {:error, :telephony_service_conflict} =
             TelephonyServices.register(
               data.first.key,
               Map.put(application(data.first.key), "provider_connection_id", "shared-app"),
               data.options
             )

    {:ok, own} =
      TelephonyServices.register(data.first.key, application(data.first.key), data.options)

    assert {:error, :telephony_service_conflict} =
             TelephonyServices.configure_platform_application(
               own.provider_connection_id,
               data.options
             )

    assert {:ok, "shared-app"} = TelephonyServices.platform_application(data.options)
  end

  defp publish(data, tenant, number) do
    source = put_in(source(), [:participants, "caller", :connection, :number], number)

    {:ok, draft} =
      Calls.save_authorized_call_spec(
        InstallationOperator.authority(),
        tenant,
        source,
        data.options
      )

    {:ok, published} =
      Calls.publish_authorized_call_spec(
        InstallationOperator.authority(),
        tenant,
        draft.call_spec_id,
        draft.revision,
        data.options
      )

    published
  end

  # Simulate pre-guard data so ingress proves its own ambiguity boundary.
  defp force_publish(draft) do
    import Ecto.Query
    alias Vxpipe.Persistence.Schema.{CallSpec, CallSpecRevision, TelephonyRoute}

    revision =
      Repo.get_by!(CallSpecRevision, call_spec_id: draft.call_spec_id, revision: draft.revision)

    now = DateTime.utc_now()

    Repo.update_all(from(s in CallSpec, where: s.id == ^draft.call_spec_id),
      set: [published_revision_id: revision.id, published_at: now]
    )

    Repo.update_all(from(r in TelephonyRoute, where: r.call_spec_revision_id == ^revision.id),
      set: [published_at: now]
    )
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
