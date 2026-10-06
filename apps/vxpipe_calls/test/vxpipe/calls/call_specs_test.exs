defmodule Vxpipe.Calls.CallSpecsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{Administration, CallSpecs}
  alias Vxpipe.Calls.TestMemoryRepository

  test "rejects application-wide carrier routing before repository lookup" do
    assert {:error, :invalid_telephony_route} =
             CallSpecs.resolve_telephony_route(:application, "phone", "+15550001000", [])
  end

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      call_spec_repository: TestMemoryRepository.call_spec_repository(repository),
      registries: registries()
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    assert {:ok, other_tenant, _issued} =
             Administration.bootstrap_tenant("Other tenant", [:admin], options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        Vxpipe.Calls.TestTelephonyServiceRepository.repository([tenant, other_tenant])
      )

    [tenant: tenant, other_tenant: other_tenant, options: options]
  end

  test "keeps a saved draft route unavailable until publication", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, draft} = CallSpecs.save(tenant.key, call_spec_input(), options)
    assert draft.revision == 1
    assert draft.published_at == nil
    assert draft.validation_errors == []
    assert [route] = draft.routes

    assert route.key =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_route(tenant.key, route.key, options)

    assert {:ok, published} =
             CallSpecs.publish(tenant.key, draft.call_spec_id, draft.revision, options)

    assert %DateTime{} = published.published_at

    assert {:ok, resolved} = CallSpecs.resolve_route(tenant.key, route.key, options)
    assert resolved.call_spec_id == draft.call_spec_id
    assert resolved.call_spec_revision == 1
    assert resolved.participant_ref == "caller"
  end

  test "isolates routes by tenant and preserves immutable revisions", %{
    tenant: tenant,
    other_tenant: other_tenant,
    options: options
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, call_spec_input(), options)
    assert {:ok, first} = CallSpecs.publish(tenant.key, first.call_spec_id, 1, options)
    assert [first_route] = first.routes

    changed = Map.put(call_spec_input(), :name, "Changed")

    assert {:ok, second} =
             CallSpecs.save(
               tenant.key,
               changed,
               Keyword.put(options, :call_spec_id, first.call_spec_id)
             )

    assert second.revision == 2
    assert {:ok, stored_first} = CallSpecs.fetch(tenant.key, first.call_spec_id, 1, options)
    assert stored_first.source["name"] == "Example"
    assert second.source["name"] == "Changed"

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_route(other_tenant.key, first_route.key, options)
  end

  test "rejects unsupported inline selections before saving", %{
    tenant: tenant,
    options: options
  } do
    unsupported =
      put_in(call_spec_input(), [:defaults, :capabilities, :model_inference], "missing-model")

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
             CallSpecs.save(tenant.key, unsupported, options)
  end

  test "rejects private material instead of persisting it in a call spec revision", %{
    tenant: tenant,
    options: options
  } do
    source = Map.put(call_spec_input(), :api_key, "must-not-be-stored")

    assert {:error, :private_call_spec_material} = CallSpecs.save(tenant.key, source, options)
  end

  test "stores provider-neutral phone intent metadata without creating a web join route", %{
    tenant: tenant,
    options: options
  } do
    source =
      call_spec_input()
      |> put_in([:participants, "assistant", :transfers], ["phone-support"])
      |> put_in([:participants, "phone-support"], %{
        type: "human",
        connection: %{
          service: "primary-phone",
          mode: "dial",
          number: "+15550001001"
        }
      })

    assert {:ok, draft} = CallSpecs.save(tenant.key, source, options)

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
      put_in(call_spec_input(), [:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "receive",
        admission: "start_call",
        number: "+15550001000"
      })

    assert {:ok, draft} = CallSpecs.save(tenant.key, source, options)
    assert draft.routes == []

    assert [route] = draft.telephony_routes
    assert route.service == "primary-phone"
    assert route.number == "+15550001000"
    assert route.participant_ref == "caller"

    assert {:error, :route_unavailable} =
             CallSpecs.resolve_telephony_route(
               {:tenant, tenant.key},
               "primary-phone",
               "+15550001000",
               options
             )

    assert {:ok, _published} =
             CallSpecs.publish(tenant.key, draft.call_spec_id, draft.revision, options)

    assert {:ok, resolved} =
             CallSpecs.resolve_telephony_route(
               {:tenant, tenant.key},
               "primary-phone",
               "+15550001000",
               options
             )

    assert resolved.call_spec_id == draft.call_spec_id
    assert resolved.call_spec_revision == draft.revision

    assert {:error, :invalid_telephony_route} =
             CallSpecs.resolve_telephony_route(
               :application,
               "primary-phone",
               "+15550001000",
               options
             )

    assert {:ok, other_draft} = CallSpecs.save(other_tenant.key, source, options)

    assert {:ok, _other_published} =
             CallSpecs.publish(
               other_tenant.key,
               other_draft.call_spec_id,
               other_draft.revision,
               options
             )

    assert {:ok, ^resolved} =
             CallSpecs.resolve_telephony_route(
               {:tenant, tenant.key},
               "primary-phone",
               "+15550001000",
               options
             )

    assert {:ok, other_resolved} =
             CallSpecs.resolve_telephony_route(
               {:tenant, other_tenant.key},
               "primary-phone",
               "+15550001000",
               options
             )

    assert other_resolved.tenant_key == other_tenant.key
  end

  test "saves and publishes a new outgoing spec without an inbound entry route", %{
    tenant: tenant,
    options: options
  } do
    source =
      call_spec_input()
      |> Map.drop([:entry_caller, :entry_receiver])
      |> Map.put(:schema_version, "20261004.01")
      |> Map.put(:outgoing_call, %{callee: "caller", handled_by: "assistant"})
      |> put_in([:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "dial",
        number: "+15550001000"
      })

    assert {:ok, draft} = CallSpecs.save(tenant.key, source, options)
    assert draft.routes == []
    assert draft.telephony_routes == []
    assert draft.validation_errors == []
    assert draft.compiled_metadata["direction"] == "outgoing"
    assert draft.compiled_metadata["ring_timeout_ms"] == 30_000

    assert {:ok, published} =
             CallSpecs.publish(tenant.key, draft.call_spec_id, draft.revision, options)

    assert published.routes == []
    assert published.telephony_routes == []
  end

  test "new incoming source saves and publishes beside executable legacy revisions", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, legacy} = CallSpecs.save(tenant.key, call_spec_input(), options)
    assert {:ok, legacy} = CallSpecs.publish(tenant.key, legacy.call_spec_id, 1, options)

    source =
      call_spec_input()
      |> Map.drop([:entry_caller, :entry_receiver])
      |> Map.put(:schema_version, "20261004.01")
      |> Map.put(:incoming_call, %{caller: "caller", handled_by: "assistant"})

    assert {:ok, modern} = CallSpecs.save(tenant.key, source, options)
    assert {:ok, modern} = CallSpecs.publish(tenant.key, modern.call_spec_id, 1, options)
    assert {:ok, stored} = CallSpecs.fetch(tenant.key, legacy.call_spec_id, 1, options)
    assert stored.source["schema_version"] == "20260915.01"
    assert stored.source["entry_caller"] == "caller"

    for revision <- [legacy, modern] do
      assert [route] = revision.routes
      assert {:ok, resolved} = CallSpecs.resolve_route(tenant.key, route.key, options)
      assert resolved.call_spec_id == revision.call_spec_id
    end
  end

  test "preparation digest includes the outgoing deadline", %{tenant: tenant, options: options} do
    source =
      call_spec_input()
      |> Map.drop([:entry_caller, :entry_receiver])
      |> Map.put(:schema_version, "20261004.01")
      |> Map.put(:outgoing_call, %{
        callee: "caller",
        handled_by: "assistant",
        ring_timeout_ms: 5_000
      })
      |> Map.put(:wait_sounds, nil)
      |> put_in([:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "dial",
        number: "+15550001000"
      })

    assert {:ok, revision} = CallSpecs.save(tenant.key, source, options)

    options =
      options ++
        [
          call_id_generator: fn -> "fixed-call" end,
          room_id_generator: fn -> "fixed-room" end,
          actor_id_generator: fn -> "fixed-actor" end
        ]

    assert {:ok, first} =
             Vxpipe.Calls.PreparedCallFactory.build(revision, %{}, :telephony, options)

    changed = %{
      revision
      | source: put_in(revision.source, ["outgoing_call", "ring_timeout_ms"], 60_000)
    }

    assert {:ok, second} =
             Vxpipe.Calls.PreparedCallFactory.build(changed, %{}, :telephony, options)

    assert first.plan.direction == :outgoing
    assert first.plan.ring_timeout_ms == 5_000
    assert second.plan.ring_timeout_ms == 60_000
    refute first.plan_digest == second.plan_digest

    assert first.plan_digest ==
             :crypto.hash(:sha256, :erlang.term_to_binary(first.plan, [:deterministic]))
  end

  defp registries do
    %{
      host_tools: %{}
    }
  end

  defp call_spec_input do
    %{
      schema_version: "20260915.01",
      name: "Example",
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
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
