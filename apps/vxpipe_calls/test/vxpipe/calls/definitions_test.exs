defmodule Vxpipe.Calls.DefinitionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{Administration, Definitions}
  alias Vxpipe.Calls.TestMemoryRepository

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      definition_repository: TestMemoryRepository.definition_repository(repository),
      registries: registries()
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    assert {:ok, other_tenant, _issued} =
             Administration.bootstrap_tenant("Other tenant", [:admin], options)

    [tenant: tenant, other_tenant: other_tenant, options: options]
  end

  test "keeps a saved draft route unavailable until publication", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, draft} = Definitions.save(tenant.key, definition_input(), options)
    assert draft.revision == 1
    assert draft.published_at == nil
    assert draft.validation_errors == []
    assert [route] = draft.routes

    assert route.key =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

    assert {:error, :route_unavailable} =
             Definitions.resolve_route(tenant.key, route.key, options)

    assert {:ok, published} =
             Definitions.publish(tenant.key, draft.definition_id, draft.revision, options)

    assert %DateTime{} = published.published_at

    assert {:ok, resolved} = Definitions.resolve_route(tenant.key, route.key, options)
    assert resolved.definition_id == draft.definition_id
    assert resolved.definition_revision == 1
    assert resolved.participant_ref == "caller"
  end

  test "isolates routes by tenant and preserves immutable revisions", %{
    tenant: tenant,
    other_tenant: other_tenant,
    options: options
  } do
    assert {:ok, first} = Definitions.save(tenant.key, definition_input(), options)
    assert {:ok, first} = Definitions.publish(tenant.key, first.definition_id, 1, options)
    assert [first_route] = first.routes

    changed = Map.put(definition_input(), :name, "Changed")

    assert {:ok, second} =
             Definitions.save(
               tenant.key,
               changed,
               Keyword.put(options, :definition_id, first.definition_id)
             )

    assert second.revision == 2
    assert {:ok, stored_first} = Definitions.fetch(tenant.key, first.definition_id, 1, options)
    assert stored_first.source["name"] == "Example"
    assert second.source["name"] == "Changed"

    assert {:error, :route_unavailable} =
             Definitions.resolve_route(other_tenant.key, first_route.key, options)
  end

  test "records unsupported feature errors and refuses publication", %{
    tenant: tenant,
    options: options
  } do
    unsupported =
      put_in(definition_input(), [:defaults, :capabilities, :model_inference], "missing-model")

    assert {:ok, draft} = Definitions.save(tenant.key, unsupported, options)
    assert [%{"code" => "call_definition_resolution_failed"}] = draft.validation_errors

    assert {:error, {:definition_not_publishable, errors}} =
             Definitions.publish(tenant.key, draft.definition_id, draft.revision, options)

    assert errors == draft.validation_errors
  end

  test "rejects private material instead of persisting it in a definition revision", %{
    tenant: tenant,
    options: options
  } do
    source = Map.put(definition_input(), :api_key, "must-not-be-stored")

    assert {:error, :private_definition_material} = Definitions.save(tenant.key, source, options)
  end

  test "stores provider-neutral phone intent metadata without creating a web join route", %{
    tenant: tenant,
    options: options
  } do
    source =
      definition_input()
      |> put_in([:participants, "assistant", :transfers], ["phone-support"])
      |> put_in([:participants, "phone-support"], %{
        type: "human",
        connection: %{
          service: "primary-phone",
          mode: "dial",
          number: "+15550001001"
        }
      })

    assert {:ok, draft} = Definitions.save(tenant.key, source, options)

    assert %{
             "admission" => "transfer",
             "mode" => "dial",
             "number" => "+15550001001",
             "service" => "primary-phone"
           } = draft.compiled_metadata["participants"]["phone-support"]["connection"]

    assert Enum.map(draft.routes, & &1.participant_ref) == ["caller"]
  end

  test "publishes an inbound phone route resolved through its configured service", %{
    tenant: tenant,
    other_tenant: other_tenant,
    options: options
  } do
    source =
      put_in(definition_input(), [:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "receive",
        admission: "start_call",
        number: "+15550001000"
      })

    assert {:ok, draft} = Definitions.save(tenant.key, source, options)
    assert draft.routes == []

    assert [route] = draft.telephony_routes
    assert route.service == "primary-phone"
    assert route.number == "+15550001000"
    assert route.participant_ref == "caller"

    assert {:error, :route_unavailable} =
             Definitions.resolve_telephony_route(
               :application,
               "primary-phone",
               "+15550001000",
               options
             )

    assert {:ok, _published} =
             Definitions.publish(tenant.key, draft.definition_id, draft.revision, options)

    assert {:ok, resolved} =
             Definitions.resolve_telephony_route(
               {:tenant, tenant.key},
               "primary-phone",
               "+15550001000",
               options
             )

    assert resolved.definition_id == draft.definition_id
    assert resolved.definition_revision == draft.revision

    assert {:ok, ^resolved} =
             Definitions.resolve_telephony_route(
               :application,
               "primary-phone",
               "+15550001000",
               options
             )

    assert {:ok, other_draft} = Definitions.save(other_tenant.key, source, options)

    assert {:ok, _other_published} =
             Definitions.publish(
               other_tenant.key,
               other_draft.definition_id,
               other_draft.revision,
               options
             )

    assert {:error, :route_unavailable} =
             Definitions.resolve_telephony_route(
               :application,
               "primary-phone",
               "+15550001000",
               options
             )

    assert {:ok, other_resolved} =
             Definitions.resolve_telephony_route(
               {:tenant, other_tenant.key},
               "primary-phone",
               "+15550001000",
               options
             )

    assert other_resolved.tenant_key == other_tenant.key
  end

  defp registries do
    %{
      capability_profiles: %{
        "test-model" => %{kind: :model_inference, provider: :test, options: %{model: "test"}}
      },
      host_tools: %{}
    }
  end

  defp definition_input do
    %{
      schema_version: "20260913.01",
      name: "Example",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
