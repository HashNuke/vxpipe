defmodule Vxpipe.Persistence.CallSpecStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{Administration, CallSpecs}
  alias Vxpipe.Persistence.{CredentialStore, CallSpecStore, Repo}
  alias Vxpipe.Persistence.Schema.{CallSpecRevision, ParticipantRoute, TelephonyRoute}

  @tenant_key "AAAAAAAAAAAAAAAA"
  @key_id "11111111-1111-4111-8111-111111111111"

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      tenant_key_generator: fn -> @tenant_key end,
      uuid_generator:
        sequence([
          @key_id,
          "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        ]),
      api_key_generator: fn -> "vxp_test-secret-value" end,
      registries: registries()
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        Vxpipe.Calls.TestTelephonyServiceRepository.repository([tenant])
      )

    [tenant: tenant, options: options]
  end

  test "persists immutable revisions and only resolves the published route", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, call_spec_input(), options)
    assert [first_route] = first.routes

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_route(tenant.key, first_route.key, options)

    assert {:ok, published} = CallSpecs.publish(tenant.key, first.call_spec_id, 1, options)
    assert [published_route] = published.routes
    assert published_route.key == first_route.key
    assert %DateTime{} = published_route.published_at

    changed = Map.put(call_spec_input(), :name, "Second")

    assert {:ok, second} =
             CallSpecs.save(
               tenant.key,
               changed,
               Keyword.put(options, :call_spec_id, first.call_spec_id)
             )

    assert second.revision == 2
    assert {:ok, stored_first} = CallSpecs.fetch(tenant.key, first.call_spec_id, 1, options)
    assert stored_first.source["name"] == "First"
    assert second.source["name"] == "Second"

    assert {:ok, published_second} =
             CallSpecs.publish(tenant.key, second.call_spec_id, 2, options)

    assert [second_route] = published_second.routes

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_route(tenant.key, first_route.key, options)

    assert {:ok, resolved_second} =
             CallSpecs.resolve_route(tenant.key, second_route.key, options)

    assert resolved_second.call_spec_revision == 2
    assert Repo.aggregate(CallSpecRevision, :count) == 2
    assert Repo.aggregate(ParticipantRoute, :count) == 2
  end

  test "tenant and route unique constraints reject cross-scope disclosure and duplicates", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, draft} = CallSpecs.save(tenant.key, call_spec_input(), options)
    assert [route] = draft.routes
    assert {:ok, _published} = CallSpecs.publish(tenant.key, draft.call_spec_id, 1, options)

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_route("BBBBBBBBBBBBBBBB", route.key, options)

    duplicate = %{route | call_spec_revision: 2}

    assert {:error, :participant_route_key_conflict} =
             CallSpecStore.insert_revision(
               Repo,
               tenant.key,
               %{draft | revision: 2, routes: [duplicate]},
               [duplicate]
             )
  end

  test "persists and resolves only published inbound telephony routes", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, draft} = CallSpecs.save(tenant.key, phone_call_spec_input(), options)
    assert draft.routes == []
    assert [route] = draft.telephony_routes
    assert Repo.aggregate(TelephonyRoute, :count) == 1

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_telephony_route(
               {:tenant, tenant.key},
               route.service,
               route.number,
               options
             )

    assert {:ok, _published} =
             CallSpecs.publish(tenant.key, draft.call_spec_id, draft.revision, options)

    assert {:ok, resolved} =
             CallSpecs.resolve_telephony_route(
               {:tenant, tenant.key},
               route.service,
               route.number,
               options
             )

    assert resolved.participant_ref == "caller"
    assert resolved.call_spec_revision == draft.revision

    assert {:error, :invalid_telephony_route} =
             CallSpecs.resolve_telephony_route(
               :application,
               route.service,
               route.number,
               options
             )
  end

  defp sequence(values) do
    key = {__MODULE__, make_ref()}
    Process.put(key, values)

    fn ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  defp registries do
    %{
      host_tools: %{}
    }
  end

  defp call_spec_input do
    %{
      schema_version: "20260915.01",
      name: "First",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp phone_call_spec_input do
    put_in(call_spec_input(), [:participants, "caller", :connection], %{
      service: "primary-phone",
      mode: "receive",
      admission: "start_call",
      number: "+15550001000"
    })
  end
end
