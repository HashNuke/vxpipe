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

  test "call spec references are the database primary key", %{tenant: tenant, options: options} do
    assert {:ok, draft} = CallSpecs.save(tenant.key, call_spec_input(), options)
    assert {id, ""} = Integer.parse(draft.call_spec_id)
    stored = Repo.get!(Vxpipe.Persistence.Schema.CallSpec, id)
    assert stored.tenant_id == Repo.get_by!(Vxpipe.Persistence.Schema.Tenant, key: tenant.key).id
    refute :public_id in Vxpipe.Persistence.Schema.CallSpec.__schema__(:fields)
    assert {:ok, fetched} = CallSpecs.fetch(tenant.key, Integer.to_string(id), 1, options)
    assert fetched.call_spec_id == draft.call_spec_id

    for invalid <- ["not-an-id", "0", "-1", "1.5", "9223372036854775808"] do
      assert {:error, :not_found} = CallSpecs.fetch(tenant.key, invalid, 1, options)
      assert {:error, :not_found} = CallSpecs.publish(tenant.key, invalid, 1, options)
    end

    assert {:ok, other, _key} =
             Administration.bootstrap_tenant(
               "Other tenant",
               [:admin],
               Keyword.put(options, :tenant_key_generator, fn -> "BBBBBBBBBBBBBBBB" end)
             )

    assert {:error, :not_found} = CallSpecs.fetch(other.key, draft.call_spec_id, 1, options)
    assert {:error, :not_found} = CallSpecs.publish(other.key, draft.call_spec_id, 1, options)

    assert {:error, :not_found} =
             CallSpecs.save(
               other.key,
               call_spec_input(),
               Keyword.put(options, :call_spec_id, draft.call_spec_id)
             )

    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 1
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

  test "save and publish retain API-authored onset choices and reject invalid field values", %{
    tenant: tenant,
    options: options
  } do
    spec_id =
      Enum.reduce([false, true], nil, fn vad, previous_id ->
        save_options =
          if previous_id, do: Keyword.put(options, :call_spec_id, previous_id), else: options

        input =
          put_in(call_spec_input(), [:defaults, :capabilities, :speech_to_text], %{
            provider: "morse",
            model: "morse",
            vad: vad
          })

        assert {:ok, saved} = CallSpecs.save(tenant.key, input, save_options)
        assert saved.source["defaults"]["capabilities"]["speech_to_text"]["vad"] == vad

        assert {:ok, published} =
                 CallSpecs.publish(tenant.key, saved.call_spec_id, saved.revision, options)

        assert published.source == saved.source

        assert {:ok, fetched} =
                 CallSpecs.fetch(tenant.key, saved.call_spec_id, saved.revision, options)

        assert fetched.source == saved.source
        saved.call_spec_id
      end)

    for invalid <- [nil, "false", 0] do
      input =
        put_in(call_spec_input(), [:defaults, :capabilities, :speech_to_text], %{
          provider: "morse",
          model: "morse",
          vad: invalid
        })

      assert {:error, error} =
               CallSpecs.save(tenant.key, input, Keyword.put(options, :call_spec_id, spec_id))

      assert error.details["path"] == ["defaults", "capabilities", "speech_to_text", "vad"]
    end
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

  test "drafts may share a number but publishing rejects another spec's active assignment", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, phone_call_spec_input(), options)
    assert {:ok, second} = CallSpecs.save(tenant.key, phone_call_spec_input(), options)
    assert {:ok, _} = CallSpecs.publish(tenant.key, first.call_spec_id, first.revision, options)

    assert {:error, :phone_number_in_use} =
             CallSpecs.publish(tenant.key, second.call_spec_id, second.revision, options)

    assert {:ok, replacement} =
             CallSpecs.save(
               tenant.key,
               phone_call_spec_input(),
               Keyword.put(options, :call_spec_id, first.call_spec_id)
             )

    assert {:ok, _} =
             CallSpecs.publish(tenant.key, first.call_spec_id, replacement.revision, options)

    assert {:ok, current} =
             CallSpecs.fetch(tenant.key, second.call_spec_id, second.revision, options)

    assert is_nil(current.published_at)
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
