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

  test "keeps a saved draft route unavailable until publication", %{tenant: tenant, options: options} do
    assert {:ok, draft} = Definitions.save(tenant.key, definition_input(), options)
    assert draft.revision == 1
    assert draft.published_at == nil
    assert draft.validation_errors == []
    assert [route] = draft.routes
    assert route.key =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

    assert {:error, :route_unavailable} = Definitions.resolve_route(tenant.key, route.key, options)

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
             Definitions.save(tenant.key, changed,
               Keyword.put(options, :definition_id, first.definition_id)
             )

    assert second.revision == 2
    assert {:ok, stored_first} = Definitions.fetch(tenant.key, first.definition_id, 1, options)
    assert stored_first.source["name"] == "Example"
    assert second.source["name"] == "Changed"

    assert {:error, :route_unavailable} =
             Definitions.resolve_route(other_tenant.key, first_route.key, options)
  end

  test "records unsupported feature errors and refuses publication", %{tenant: tenant, options: options} do
    unsupported = put_in(definition_input(), [:defaults, :capabilities, :model_inference], "missing-model")

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
      schema_version: "20260911.02",
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
