defmodule Vxpipe.Persistence.OperatorTelephonyApplicationsTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    InstallationOperator,
    OperatorTelephonyApplications,
    ProviderCredentials,
    TelephonyServices
  }

  alias Vxpipe.Persistence.{
    AdminStore,
    CallSpecStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    TelephonyServiceStore
  }

  setup do
    {:ok, keyring} =
      CredentialKeyring.new("applications", %{"applications" => :crypto.strong_rand_bytes(32)})

    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      telephony_service_repository: {TelephonyServiceStore, context},
      admin_repository: {AdminStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, first, _} =
      Administration.bootstrap_tenant("First application tenant", [:admin], options)

    {:ok, second, _} =
      Administration.bootstrap_tenant("Second application tenant", [:admin], options)

    {:ok, platform} = credential(:platform, options)

    %{
      first: first,
      second: second,
      platform: platform,
      context: context,
      options: options,
      operator: InstallationOperator.authority()
    }
  end

  test "operator applications inherit credentials while each mapping remains tenant-owned",
       data do
    for tenant <- [data.first, data.second] do
      assert {:ok, application} = create(data, tenant)

      assert Map.keys(application) |> Enum.sort() == [
               :id,
               :name,
               :outbound_number,
               :provider_connection_id
             ]

      assert application.name == "support"
      assert {:ok, snapshot} = TelephonyServices.resolve(tenant.key, "support", data.options)
      assert snapshot.service.id == application.id
      assert snapshot.service.credential_name == "telnyx"
      assert snapshot.service.credential_owner == :platform
      assert snapshot.service.credential_id == data.platform.id
      assert snapshot.service.ingress_key =~ "telnyx-"
    end

    {:ok, own} = credential(data.first.key, data.options)
    assert {:ok, snapshot} = TelephonyServices.resolve(data.first.key, "support", data.options)
    assert snapshot.service.credential_id == own.id
  end

  test "editing preserves stable identity and rejects prepared references to the old application",
       data do
    {:ok, application} = create(data, data.first)
    {:ok, before} = TelephonyServices.resolve(data.first.key, "support", data.options)
    reference = TelephonyServices.reference(before.service)

    changes = %{
      "provider_connection_id" => "replacement-application",
      "outbound_number" => "+15550002000"
    }

    assert {:ok, updated} =
             OperatorTelephonyApplications.update(
               data.operator,
               data.first.key,
               application.id,
               changes,
               data.options
             )

    assert updated.id == application.id
    assert updated.name == "support"
    assert updated.outbound_number == "+15550002000"
    assert {:ok, after_edit} = TelephonyServices.resolve(data.first.key, "support", data.options)
    assert after_edit.service.ingress_key == before.service.ingress_key
    assert after_edit.service.credential_id == before.service.credential_id

    assert {:error, :telephony_service_not_found} =
             TelephonyServices.fetch_telnyx_application(
               before.service.provider_connection_id,
               data.options
             )

    assert {:error, {:provider_credential_unavailable, ["phone"]}} =
             TelephonyServiceStore.with_active(
               data.context,
               data.first.key,
               [%{name: "support", path: ["phone"], reference: reference}],
               fn -> flunk("stale application reached write") end
             )

    assert {:error, :telephony_service_not_found} =
             OperatorTelephonyApplications.update(
               data.operator,
               data.second.key,
               application.id,
               changes,
               data.options
             )

    assert {:error, :invalid_telephony_service} =
             OperatorTelephonyApplications.update(
               data.operator,
               data.first.key,
               application.id,
               %{"name" => "renamed"},
               data.options
             )

    assert {:error, :installation_operator_required} =
             OperatorTelephonyApplications.update(
               nil,
               data.first.key,
               application.id,
               changes,
               data.options
             )
  end

  test "conflicting applications and missing tenant verifiers cannot overwrite a mapping", data do
    {:ok, first} = create(data, data.first)
    {:ok, second} = create(data, data.second)

    assert {:error, :telephony_service_conflict} =
             OperatorTelephonyApplications.update(
               data.operator,
               data.second.key,
               second.id,
               %{"provider_connection_id" => first.provider_connection_id},
               data.options
             )

    assert {:ok, existing} = TelephonyServices.fetch(data.second.key, "support", data.options)
    assert existing.provider_connection_id == second.provider_connection_id

    {:ok, _} =
      ProviderCredentials.provision(
        data.second.key,
        "telnyx",
        "telnyx",
        "api_key",
        %{"api_key" => "synthetic-no-verifier"},
        data.options
      )

    assert {:error, :provider_credential_unavailable} =
             OperatorTelephonyApplications.update(
               data.operator,
               data.second.key,
               second.id,
               %{"outbound_number" => "+15550002000"},
               data.options
             )

    assert {:error, :provider_credential_unavailable} =
             OperatorTelephonyApplications.create(
               data.operator,
               data.second.key,
               %{attributes(data.second) | "name" => "another"},
               data.options
             )

    assert {:ok, %{applications: [stored]}} =
             OperatorTelephonyApplications.list(data.operator, data.second.key, data.options)

    assert stored.outbound_number == nil
  end

  test "progress includes only the tenant's current published number routes and marks ambiguity",
       data do
    {:ok, _} = create(data, data.first)
    {:ok, _} = create(data, data.second)
    {:ok, draft} = save(data, data.first, "+15550001000")
    assert {:ok, %{applications: [%{published_routes: []}]}} = directory(data, data.first)
    publish(data, data.first, draft)
    {:ok, other} = save(data, data.second, "+15550001000")
    publish(data, data.second, other)

    assert {:ok, %{applications: [%{published_routes: [route]}], truncated: false}} =
             directory(data, data.first)

    assert route.number == "+15550001000"
    assert route.call_spec_id == draft.call_spec_id
    assert route.call_spec_revision == 1
    assert route.ambiguous == false

    {:ok, revision} = save(data, data.first, "+15550001001", call_spec_id: draft.call_spec_id)
    publish(data, data.first, revision)
    assert {:ok, %{applications: [%{published_routes: [current]}]}} = directory(data, data.first)
    assert current.number == "+15550001001"
    assert current.call_spec_revision == 2

    {:ok, duplicate} = save(data, data.first, "+15550001001")
    publish(data, data.first, duplicate)

    assert {:ok, %{applications: [%{published_routes: routes}]} = safe} =
             directory(data, data.first)

    assert length(routes) == 2
    assert Enum.all?(routes, & &1.ambiguous)
    refute inspect(safe) =~ "synthetic-application-secret"
    refute inspect(safe) =~ "public_key"
    refute inspect(safe) =~ "encrypted_payload"
  end

  test "application inventory is bounded independently of credential inventory", data do
    for index <- 1..101 do
      label = index |> Integer.to_string() |> String.pad_leading(3, "0")

      assert {:ok, _} =
               OperatorTelephonyApplications.create(
                 data.operator,
                 data.first.key,
                 %{"name" => "phone-#{label}", "provider_connection_id" => "app-#{label}"},
                 data.options
               )
    end

    assert {:ok, %{applications: applications, truncated: true}} = directory(data, data.first)
    assert length(applications) == 100
    assert hd(applications).name == "phone-001"
    assert List.last(applications).name == "phone-100"
  end

  test "a duplicate beyond the route display limit still makes the visible number ambiguous",
       data do
    {:ok, _} = create(data, data.first)
    {:ok, draft} = save(data, data.first, "+15550001000")
    publish(data, data.first, draft)
    tenant = Repo.get_by!(Vxpipe.Persistence.Schema.Tenant, key: data.first.key)

    spec =
      Repo.get_by!(Vxpipe.Persistence.Schema.CallSpec,
        public_id: draft.call_spec_id,
        tenant_id: tenant.id
      )

    route_schema = Vxpipe.Persistence.Schema.TelephonyRoute

    Repo.delete_all(
      from(r in route_schema, where: r.call_spec_revision_id == ^spec.published_revision_id)
    )

    timestamp = DateTime.utc_now()
    # Populate the directory boundary directly; the smaller publication test above
    # proves which revisions qualify through the owning save/publish API.
    rows =
      for index <- 1..501 do
        %{
          tenant_id: tenant.id,
          call_spec_revision_id: spec.published_revision_id,
          participant_ref: "caller-#{index}",
          service: "support",
          number: "+155500#{10000 + min(index, 500)}",
          published_at: timestamp,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end

    assert {501, _} = Repo.insert_all(route_schema, rows)

    assert {:ok, %{applications: [%{published_routes: routes}], truncated: true}} =
             directory(data, data.first)

    assert length(routes) == 500
    assert List.last(routes).number == "+15550010500"
    assert List.last(routes).ambiguous
    refute hd(routes).ambiguous
  end

  defp create(data, tenant),
    do:
      OperatorTelephonyApplications.create(
        data.operator,
        tenant.key,
        attributes(tenant),
        data.options
      )

  defp directory(data, tenant),
    do: OperatorTelephonyApplications.list(data.operator, tenant.key, data.options)

  defp attributes(tenant),
    do: %{"name" => "support", "provider_connection_id" => "application-#{tenant.key}"}

  defp credential(owner, options),
    do:
      ProviderCredentials.provision(
        owner,
        "telnyx",
        "telnyx",
        "api_key",
        %{"api_key" => "synthetic-application-secret", "public_key" => Base.encode64(<<1::256>>)},
        options
      )

  defp save(data, tenant, number, extra \\ []),
    do:
      Calls.save_authorized_call_spec(
        data.operator,
        tenant.key,
        source(number),
        Keyword.merge(data.options, extra)
      )

  defp publish(data, tenant, draft) do
    assert {:ok, _} =
             Calls.publish_authorized_call_spec(
               data.operator,
               tenant.key,
               draft.call_spec_id,
               draft.revision,
               data.options
             )
  end

  defp source(number) do
    %{
      schema_version: "20260915.01",
      name: "Phone application",
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
            number: number,
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
