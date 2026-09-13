defmodule Vxpipe.Calls.AdmissionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository}

  @now ~U[2026-09-09 10:00:00.000000Z]
  @call_id "5fd13da8-05c3-4a3e-9eaa-17587fa46e92"
  @room_id "61f0d53f-12e8-4ab4-b0bd-a0747f4c1966"
  @actor_id "dd0e7153-16ac-4d34-a80e-8b28f5b8a0ae"
  @token_id "70572cb7-e280-4ae6-bd09-f1e49c6232c9"
  @token "vxj_test-only-prepared-call-token"

  setup context do
    repository = start_supervised!(TestMemoryRepository)

    base_options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      definition_repository: TestMemoryRepository.definition_repository(repository),
      call_repository: TestMemoryRepository.call_repository(repository),
      registries: registries()
    ]

    assert {:ok, tenant, issued_key} =
             Administration.bootstrap_tenant("Admission tenant", [:calls], base_options)

    assert {:ok, principal} =
             Administration.authenticate(tenant.key, issued_key.secret, :calls, base_options)

    input =
      case Map.fetch(context, :wait_sounds) do
        {:ok, sounds} ->
          Map.merge(definition_input(), %{schema_version: "20260914.01", wait_sounds: sounds})

        :error ->
          definition_input()
      end

    assert {:ok, draft} = Calls.save_definition(tenant.key, input, base_options)

    assert {:ok, published} =
             Calls.publish_definition(tenant.key, draft.definition_id, 1, base_options)

    assert [caller_route] = Enum.filter(published.routes, &(&1.participant_ref == "caller"))

    options =
      base_options ++
        [
          now: @now,
          call_id_generator: fn -> @call_id end,
          room_id_generator: fn -> @room_id end,
          actor_id_generator: fn -> @actor_id end,
          token_id_generator: fn -> @token_id end,
          join_token_generator: fn -> @token end
        ]

    [
      caller_route: caller_route,
      options: options,
      principal: principal,
      repository: repository,
      tenant: tenant
    ]
  end

  test "prepares a pinned call and first single-use token without starting runtime work",
       context do
    initial_variables = %{"order" => %{"id" => "ORD-1042"}}

    assert {:ok, prepared_call, issued_token} =
             Calls.prepare_call(
               context.principal,
               context.caller_route.key,
               initial_variables,
               context.options
             )

    assert prepared_call.id == @call_id
    assert prepared_call.room_id == @room_id
    assert prepared_call.state == :prepared
    assert prepared_call.created_at == @now
    assert prepared_call.started_at == nil
    assert prepared_call.ended_at == nil
    assert prepared_call.initial_variables == initial_variables
    assert prepared_call.plan.call_id == @call_id
    assert prepared_call.plan.room_id == @room_id
    assert prepared_call.plan.definition_revision == 1
    assert prepared_call.plan.call_variables.sections["order"].value == initial_variables["order"]
    assert is_binary(prepared_call.plan_digest)
    assert byte_size(prepared_call.plan_digest) == 32
    assert map_size(prepared_call.plan.wait_sound_assets.assets) == 3
    assert prepared_call.plan.wait_sound_assets.slots.transfer_joining != nil

    assert issued_token.secret == @token
    assert issued_token.call_id == @call_id
    assert issued_token.participant_key == context.caller_route.key
    assert issued_token.participant_ref == "caller"
    assert issued_token.expires_at == DateTime.add(@now, 300, :second)

    refute inspect(prepared_call) =~ "ORD-1042"
    refute inspect(issued_token) =~ @token

    assert {:ok, stored} = Calls.fetch_call(context.tenant.key, @call_id, context.options)
    assert stored.initial_variables == initial_variables
    assert TestMemoryRepository.admissions(context.repository) == []
  end

  @tag wait_sounds: %{transfer_joining: "http://127.0.0.1/private.wav"}
  test "rejects an unsafe wait asset before persisting a call or issuing admission", context do
    assert {:error,
            %{
              code: :wait_sound_unavailable,
              details: %{"path" => ["wait_sounds", "transfer_joining"]}
            }} =
             Calls.prepare_call(context.principal, context.caller_route.key, %{}, context.options)

    assert :error = Calls.fetch_call(context.tenant.key, @call_id, context.options)

    assert TestMemoryRepository.admissions(context.repository) == []
  end

  test "validates supplied variables without requiring missing sections", context do
    assert {:ok, call, _token} =
             Calls.prepare_call(
               context.principal,
               context.caller_route.key,
               %{},
               context.options
             )

    assert call.plan.call_variables.sections["order"].value == nil

    assert {:error, error} =
             Calls.prepare_call(
               context.principal,
               context.caller_route.key,
               %{"order" => %{"id" => 42}},
               context.options
             )

    assert error.code == :call_definition_resolution_failed
  end

  test "rejects a published web route that is not the entry caller", context do
    assert {:ok, draft} =
             Calls.save_definition(
               context.tenant.key,
               definition_input("observer"),
               Keyword.delete(context.options, :definition_id)
             )

    assert {:ok, published} =
             Calls.publish_definition(
               context.tenant.key,
               draft.definition_id,
               draft.revision,
               context.options
             )

    assert observer_route = Enum.find(published.routes, &(&1.participant_ref == "observer"))

    assert {:error, :participant_not_entry_caller} =
             Calls.prepare_call(context.principal, observer_route.key, %{}, context.options)
  end

  test "accepts an explicitly longer token lifetime and preserves independent tokens", context do
    assert {:ok, call, first} = prepare(context)

    assert {:ok, second} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.caller_route.key,
               Keyword.merge(context.options,
                 join_token_ttl_seconds: 900,
                 token_id_generator: fn -> "90a191c1-66b7-4b07-b85a-08e6464d3e96" end,
                 join_token_generator: fn -> "vxj_test-only-second-token" end
               )
             )

    assert first.expires_at == DateTime.add(@now, 300, :second)
    assert second.expires_at == DateTime.add(@now, 900, :second)
    assert first.id != second.id
  end

  test "treats repeated creation as separate prepared calls", context do
    assert {:ok, first_call, _first_token} = prepare(context)

    second_options =
      Keyword.merge(context.options,
        call_id_generator: fn -> "43dde054-c3c6-447f-b685-b8291b79de86" end,
        room_id_generator: fn -> "2df93a20-5736-4bc8-b1a2-9e1ec94df74b" end,
        actor_id_generator: fn -> "e6798777-c777-40ee-a3af-e690550b1dfb" end,
        token_id_generator: fn -> "64dfa851-ef61-4e07-af7f-089d9b00368f" end,
        join_token_generator: fn -> "vxj_test-only-repeated-creation-token" end
      )

    assert {:ok, second_call, _second_token} =
             Calls.prepare_call(
               context.principal,
               context.caller_route.key,
               %{"order" => %{"id" => "ORD-1042"}},
               second_options
             )

    assert first_call.id != second_call.id
    assert first_call.room_id != second_call.room_id

    assert {:ok, ^first_call} =
             Calls.fetch_call(context.tenant.key, first_call.id, context.options)

    assert {:ok, ^second_call} =
             Calls.fetch_call(context.tenant.key, second_call.id, context.options)
  end

  test "claims one token atomically and binds it to the requested URL scope", context do
    assert {:ok, call, token} = prepare(context)

    expected_scope = %{
      tenant_key: context.tenant.key,
      call_id: call.id,
      participant_key: context.caller_route.key
    }

    for mismatched_scope <- [
          %{expected_scope | tenant_key: "another-tenant"},
          %{expected_scope | call_id: "7996906c-9976-4083-8730-6577d08f96aa"},
          %{expected_scope | participant_key: "another-participant-route"}
        ] do
      assert {:error, :token_scope_mismatch} =
               Calls.claim_join_token(token.secret, mismatched_scope, context.options)
    end

    assert {:ok, claim} = Calls.claim_join_token(token.secret, expected_scope, context.options)
    assert claim.call.id == call.id
    assert claim.call.state == :admitting
    assert claim.participant_ref == "caller"
    assert claim.accepted_at == @now
    refute inspect(claim) =~ token.secret

    assert {:error, :token_already_claimed} =
             Calls.claim_join_token(token.secret, expected_scope, context.options)
  end

  test "keeps the prepared plan pinned after a newer definition revision is published", context do
    assert {:ok, call, _first_token} = prepare(context)

    revised_definition =
      put_in(definition_input(), [:participants, "assistant", :prompt], "Revised prompt.")

    assert {:ok, draft} =
             Calls.save_definition(
               context.tenant.key,
               revised_definition,
               Keyword.put(context.options, :definition_id, call.definition_id)
             )

    assert draft.revision == 2

    assert {:ok, published} =
             Calls.publish_definition(
               context.tenant.key,
               draft.definition_id,
               draft.revision,
               context.options
             )

    assert published.revision == 2

    assert {:ok, second_token} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.caller_route.key,
               Keyword.merge(context.options,
                 token_id_generator: fn -> "90a191c1-66b7-4b07-b85a-08e6464d3e97" end,
                 join_token_generator: fn -> "vxj_test-only-pinned-plan-token" end
               )
             )

    assert {:ok, claim} =
             Calls.claim_join_token(
               second_token.secret,
               scope(context, call),
               context.options
             )

    assert claim.call.definition_revision == 1
    assert claim.call.plan.definition_revision == 1
    assert claim.call.plan.participants["assistant"].prompt == "Help the caller."
  end

  test "pins the tenant call-duration setting while preparing an omitted definition limit",
       context do
    duration_options =
      Keyword.put(context.options, :call_duration,
        max_duration_ms: 120_000,
        tenants: %{context.tenant.key => [max_duration_ms: 90_000]}
      )

    assert {:ok, call, _token} =
             Calls.prepare_call(
               context.principal,
               context.caller_route.key,
               %{},
               duration_options
             )

    assert call.plan.max_duration_ms == 90_000

    changed_options =
      Keyword.put(context.options, :call_duration,
        max_duration_ms: 150_000,
        tenants: %{context.tenant.key => [max_duration_ms: 180_000]}
      )

    assert {:ok, stored} = Calls.fetch_call(context.tenant.key, call.id, changed_options)
    assert stored.plan.max_duration_ms == 90_000
  end

  test "does not claim expired tokens and lets distinct tokens share admission exclusion",
       context do
    assert {:ok, call, first} = prepare(context)

    assert {:ok, second} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.caller_route.key,
               Keyword.merge(context.options,
                 token_id_generator: fn -> "993c589a-a306-48ff-a88a-9a59a92699ba" end,
                 join_token_generator: fn -> "vxj_test-only-competing-token" end
               )
             )

    scope = %{
      tenant_key: context.tenant.key,
      call_id: call.id,
      participant_key: context.caller_route.key
    }

    expired_options = Keyword.put(context.options, :now, DateTime.add(@now, 301, :second))
    assert {:error, :token_expired} = Calls.claim_join_token(first.secret, scope, expired_options)

    assert {:ok, _claim} = Calls.claim_join_token(second.secret, scope, context.options)

    assert {:error, :participant_admission_unavailable} =
             Calls.claim_join_token(first.secret, scope, context.options)
  end

  test "projects the first actual live-start occurrence without resetting it", context do
    assert {:ok, call, token} = prepare(context)

    assert {:ok, claim} =
             Calls.claim_join_token(token.secret, scope(context, call), context.options)

    started_at = DateTime.add(@now, 10, :second)

    assert {:ok, running} =
             Calls.mark_call_started(
               claim,
               "rinc_accepted-runtime",
               started_at,
               context.options
             )

    assert running.state == :running
    assert running.started_at == started_at
    assert running.incarnation_id == "rinc_accepted-runtime"
    assert running.ended_at == nil

    assert {:ok, duplicate} =
             Calls.mark_call_started(
               claim,
               "rinc_should-not-replace",
               DateTime.add(started_at, 30, :second),
               context.options
             )

    assert duplicate.started_at == started_at
    assert duplicate.incarnation_id == "rinc_accepted-runtime"
  end

  test "records a bounded pre-live failure without inventing a start time", context do
    assert {:ok, call, token} = prepare(context)

    assert {:ok, claim} =
             Calls.claim_join_token(token.secret, scope(context, call), context.options)

    assert {:ok, failed} =
             Calls.mark_call_failed(claim, :room_start_failed, context.options)

    assert failed.state == :failed
    assert failed.started_at == nil
    assert failed.ended_at == @now
    assert failed.incarnation_id == nil
    assert failed.terminal_reason == :room_start_failed

    assert {:error, :call_unavailable} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.caller_route.key,
               context.options
             )
  end

  defp prepare(context) do
    Calls.prepare_call(
      context.principal,
      context.caller_route.key,
      %{"order" => %{"id" => "ORD-1042"}},
      context.options
    )
  end

  defp scope(context, call) do
    %{
      tenant_key: context.tenant.key,
      call_id: call.id,
      participant_key: context.caller_route.key
    }
  end

  defp registries do
    %{
      capability_profiles: %{
        "test-model" => %{kind: :model_inference, provider: :test, options: %{model: "test"}}
      },
      host_tools: %{}
    }
  end

  defp definition_input(extra_web_participant \\ nil) do
    participants = %{
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

    participants =
      if extra_web_participant do
        Map.put(participants, extra_web_participant, %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        })
      else
        participants
      end

    %{
      schema_version: "20260913.01",
      name: "Admission example",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"id" => %{"type" => "string"}},
              "required" => ["id"],
              "additionalProperties" => false
            }
          }
        }
      },
      participants: participants
    }
  end
end
