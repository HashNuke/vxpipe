defmodule Vxpipe.Persistence.CallStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CallStore, CredentialStore, DefinitionStore, Repo}
  alias Vxpipe.Persistence.Schema.Admission, as: StoredAdmission
  alias Vxpipe.Persistence.Schema.Call, as: StoredCall
  alias Vxpipe.Persistence.Schema.JoinToken, as: StoredJoinToken

  @tenant_key "AAAAAAAAAAAAAAAA"
  @key_id "11111111-1111-4111-8111-111111111111"
  @definition_id "22222222-2222-4222-8222-222222222222"
  @route_id "33333333-3333-4333-8333-333333333333"
  @call_id "44444444-4444-4444-8444-444444444444"
  @room_id "55555555-5555-4555-8555-555555555555"
  @actor_id "66666666-6666-4666-8666-666666666666"
  @token_id "77777777-7777-4777-8777-777777777777"
  @api_key "vxp_test-only-call-store-key"
  @join_token "vxj_test-only-persisted-token"
  @now ~U[2026-09-09 11:00:00.000000Z]

  setup do
    repository_options = [
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      call_repository: {CallStore, Repo},
      tenant_key_generator: fn -> @tenant_key end,
      uuid_generator: sequence([@key_id, @definition_id, @route_id]),
      api_key_generator: fn -> @api_key end,
      registries: registries()
    ]

    assert {:ok, tenant, issued_key} =
             Administration.bootstrap_tenant("Stored calls", [:calls], repository_options)

    assert {:ok, principal} =
             Administration.authenticate(tenant.key, issued_key.secret, :calls, repository_options)

    assert {:ok, draft} = Calls.save_definition(tenant.key, definition_input(), repository_options)
    assert {:ok, published} = Calls.publish_definition(tenant.key, draft.definition_id, 1, repository_options)
    assert [route] = published.routes

    options =
      repository_options ++
        [
          now: @now,
          call_id_generator: fn -> @call_id end,
          room_id_generator: fn -> @room_id end,
          actor_id_generator: fn -> @actor_id end,
          token_id_generator: fn -> @token_id end,
          join_token_generator: fn -> @join_token end
        ]

    [options: options, principal: principal, route: route, tenant: tenant]
  end

  test "atomically stores and reconstructs a private prepared call and its first token", context do
    variables = %{"order" => %{"id" => "ORD-2048"}}

    assert {:ok, prepared, issued} =
             Calls.prepare_call(context.principal, context.route.key, variables, context.options)

    assert prepared.id == @call_id
    assert prepared.started_at == nil
    assert prepared.plan.call_variables.sections["order"].value == variables["order"]

    assert %StoredCall{} = stored_call = Repo.get_by!(StoredCall, public_id: @call_id)
    assert stored_call.state == :prepared
    assert stored_call.initial_variables == variables
    assert stored_call.started_at == nil
    assert is_binary(stored_call.resolved_plan)
    refute inspect(stored_call) =~ "ORD-2048"

    assert %StoredJoinToken{} = stored_token =
             Repo.get_by!(StoredJoinToken, public_id: @token_id)

    assert stored_token.digest == :crypto.hash(:sha256, issued.secret)
    assert stored_token.consumed_at == nil
    refute Map.has_key?(Map.from_struct(stored_token), :secret)
    refute inspect(stored_token) =~ issued.secret

    assert {:ok, reloaded} = Calls.fetch_call(context.tenant.key, @call_id, context.options)
    assert reloaded.initial_variables == variables
    assert reloaded.plan == prepared.plan
    assert reloaded.plan_digest == prepared.plan_digest
    assert Repo.aggregate(StoredCall, :count) == 1
    assert Repo.aggregate(StoredJoinToken, :count) == 1
  end

  test "rolls back the call when its first token cannot be stored", context do
    assert {:ok, _first_call, _first_token} = prepare(context)

    second_options =
      Keyword.merge(context.options,
        call_id_generator: fn -> "88888888-8888-4888-8888-888888888888" end,
        room_id_generator: fn -> "99999999-9999-4999-8999-999999999999" end,
        actor_id_generator: fn -> "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" end,
        token_id_generator: fn -> "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" end
      )

    assert {:error, :join_token_conflict} =
             Calls.prepare_call(context.principal, context.route.key, %{}, second_options)

    assert Repo.aggregate(StoredCall, :count) == 1
    assert Repo.aggregate(StoredJoinToken, :count) == 1
  end

  test "atomically accepts only one of two tokens for the same participant", context do
    assert {:ok, call, first} = prepare(context)

    second_options =
      Keyword.merge(context.options,
        token_id_generator: fn -> "cccccccc-cccc-4ccc-8ccc-cccccccccccc" end,
        join_token_generator: fn -> "vxj_test-only-second-persisted-token" end
      )

    assert {:ok, second} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.route.key,
               second_options
             )

    scope = scope(context, call)

    results =
      [first.secret, second.secret]
      |> Task.async_stream(
        &Calls.claim_join_token(&1, scope, context.options),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _claim}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, :participant_admission_unavailable}, &1)
           ) == 1

    assert Repo.aggregate(StoredAdmission, :count) == 1

    assert Repo.aggregate(
             from(token in StoredJoinToken, where: not is_nil(token.consumed_at)),
             :count
           ) == 1
    assert Repo.get_by!(StoredCall, public_id: call.id).state == :admitting
  end

  test "consumes one token once when the same token races itself", context do
    assert {:ok, call, token} = prepare(context)
    scope = scope(context, call)

    results =
      1..2
      |> Task.async_stream(
        fn _attempt -> Calls.claim_join_token(token.secret, scope, context.options) end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _claim}, &1)) == 1
    assert Enum.count(results, &match?({:error, :token_already_claimed}, &1)) == 1
    assert Repo.aggregate(StoredAdmission, :count) == 1
  end

  test "keeps an expired token unused and accepts an issued token after key revocation", context do
    assert {:ok, call, expired} = prepare(context)
    scope = scope(context, call)
    later = Keyword.put(context.options, :now, DateTime.add(@now, 301, :second))

    assert {:error, :token_expired} = Calls.claim_join_token(expired.secret, scope, later)
    assert Repo.get_by!(StoredJoinToken, public_id: expired.id).consumed_at == nil
    assert Repo.get_by!(StoredCall, public_id: call.id).state == :prepared

    fresh_options =
      Keyword.merge(later,
        token_id_generator: fn -> "dddddddd-dddd-4ddd-8ddd-dddddddddddd" end,
        join_token_generator: fn -> "vxj_test-only-post-revocation-token" end
      )

    assert {:ok, fresh} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.route.key,
               fresh_options
             )

    assert {:ok, _revoked} =
             Administration.revoke_api_key(
               context.tenant.key,
               context.principal.api_key_id,
               later
             )

    assert {:ok, claim} = Calls.claim_join_token(fresh.secret, scope, fresh_options)
    assert claim.call.id == call.id
  end

  test "persists the first live-start occurrence idempotently", context do
    assert {:ok, call, token} = prepare(context)
    assert {:ok, claim} = Calls.claim_join_token(token.secret, scope(context, call), context.options)
    started_at = DateTime.add(@now, 12, :second)

    assert {:ok, running} =
             Calls.mark_call_started(claim, "rinc_persisted", started_at, context.options)

    assert running.state == :running
    assert running.started_at == started_at
    assert running.incarnation_id == "rinc_persisted"

    assert {:ok, duplicate} =
             Calls.mark_call_started(
               claim,
               "rinc_not_replacement",
               DateTime.add(started_at, 20, :second),
               context.options
             )

    assert duplicate.started_at == started_at
    assert duplicate.incarnation_id == "rinc_persisted"
  end

  test "persists a terminal pre-live failure with no start time", context do
    assert {:ok, call, token} = prepare(context)
    assert {:ok, claim} = Calls.claim_join_token(token.secret, scope(context, call), context.options)

    assert {:ok, failed} =
             Calls.mark_call_failed(claim, :room_start_failed, context.options)

    assert failed.state == :failed
    assert failed.started_at == nil
    assert failed.ended_at == @now
    assert failed.terminal_reason == :room_start_failed

    assert %StoredCall{
             state: :failed,
             started_at: nil,
             terminal_reason: :room_start_failed
           } = Repo.get_by!(StoredCall, public_id: call.id)
  end

  defp prepare(context) do
    Calls.prepare_call(
      context.principal,
      context.route.key,
      %{"order" => %{"id" => "ORD-2048"}},
      context.options
    )
  end

  defp scope(context, call) do
    %{
      tenant_key: context.tenant.key,
      call_id: call.id,
      participant_key: context.route.key
    }
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
      capability_profiles: %{
        "test-model" => %{kind: :model_inference, provider: :test, options: %{model: "test"}}
      },
      host_tools: %{}
    }
  end

  defp definition_input do
    %{
      schema_version: "20260909.01",
      name: "Persistence admission",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"id" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          variable_permissions: %{"order" => ["read"]},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
