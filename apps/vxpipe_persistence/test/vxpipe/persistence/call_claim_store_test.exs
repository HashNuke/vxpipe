defmodule Vxpipe.Persistence.CallClaimStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    PreparedCallFactory,
    PublicId,
    TestTelephonyServiceRepository
  }

  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.{Call, JoinToken}

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Shared claims", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([tenant])
      )

    {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)
    %{tenant: tenant.key, actor: actor, options: options, published: published}
  end

  test "web claims persist exact variables with no token and share outgoing idempotency", c do
    variables = %{"order" => %{"id" => "nested-order", "items" => [%{"count" => 2}]}}

    assert {:ok, call} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               variables,
               nil,
               "shared-key",
               c.options
             )

    assert call.state == :prepared
    assert {:ok, loaded} = Calls.fetch_call(c.tenant, call.id, c.options)
    assert loaded.initial_variables == variables
    assert loaded.plan.call_variables.sections["order"].value == variables["order"]
    assert Repo.aggregate(Call, :count) == 1
    assert Repo.aggregate(JoinToken, :count) == 0

    assert {:duplicate, ^loaded} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               variables,
               nil,
               "shared-key",
               c.options
             )

    assert {:error, :idempotency_conflict} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               nil,
               "shared-key",
               c.options
             )

    outgoing =
      source()
      |> Map.delete(:incoming_call)
      |> Map.put(:outgoing_call, %{
        callee: "caller",
        handled_by: "assistant",
        ring_timeout_ms: 5_000
      })
      |> put_in([:participants, "caller", :connection], %{
        service: "primary-phone",
        mode: "dial",
        number: "+15550001000"
      })

    {:ok, draft} = Calls.save_call_spec(c.tenant, outgoing, c.options)
    {:ok, published} = Calls.publish_call_spec(c.tenant, draft.call_spec_id, 1, c.options)

    assert {:error, :idempotency_conflict} =
             Calls.claim_outgoing_call(
               c.actor,
               published.call_spec_id,
               %{},
               "shared-key",
               c.options
             )

    assert Repo.aggregate(Call, :count) == 1
  end

  test "atomic web claims recover unique-key races after rollback and authorize inside insertion",
       c do
    {:ok, prepared} = PreparedCallFactory.build(c.published, %{}, :web, c.options)

    first = %{
      prepared
      | idempotency_key: "race",
        idempotency_digest: :crypto.hash(:sha256, "same")
    }

    authorize = fn ->
      assert Repo.in_transaction?()
      {:ok, :authorized}
    end

    assert {:ok, stored} = CallStore.claim_call(Repo, first, authorize)
    raced = %{first | id: PublicId.uuid(), room_id: PublicId.uuid()}
    assert {:duplicate, duplicate} = CallStore.claim_call(Repo, raced, authorize)
    assert duplicate.id == stored.id

    assert {:error, :idempotency_conflict} =
             CallStore.claim_call(
               Repo,
               %{raced | idempotency_digest: :crypto.hash(:sha256, "different")},
               authorize
             )

    denied = %{raced | idempotency_key: "denied"}

    assert {:error, :credential_unavailable} =
             CallStore.claim_call(Repo, denied, fn ->
               assert Repo.in_transaction?()
               {:error, :credential_unavailable}
             end)

    assert Repo.aggregate(Call, :count) == 1
    assert Repo.aggregate(JoinToken, :count) == 0
  end

  test "token defaults remain pinned across publication and enforce single use and terminal denial",
       c do
    assert {:ok, call} =
             Calls.claim_call(
               c.actor,
               c.tenant,
               c.published.call_spec_id,
               %{},
               nil,
               nil,
               c.options
             )

    options = Keyword.put(c.options, :call_spec_id, c.published.call_spec_id)
    {:ok, second} = Calls.save_call_spec(c.tenant, source(), options)
    {:ok, _published} = Calls.publish_call_spec(c.tenant, second.call_spec_id, 2, c.options)
    assert {:ok, token} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
    assert token.participant_key in Enum.map(c.published.routes, & &1.key)
    assert DateTime.diff(token.expires_at, token.issued_at) == 300
    assert Repo.aggregate(JoinToken, :count) == 1
    scope = %{tenant_key: c.tenant, call_id: call.id, participant_key: token.participant_key}
    assert {:ok, claim} = Calls.claim_join_token(token.secret, scope, c.options)
    assert claim.call.call_spec_revision == 1

    assert {:error, :token_already_claimed} =
             Calls.claim_join_token(token.secret, scope, c.options)

    assert {:ok, _failed} = Calls.mark_call_failed(claim, :room_start_failed, c.options)

    assert {:error, :call_unavailable} =
             Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)

    assert Repo.aggregate(JoinToken, :count) == 1
  end

  defp source do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              type: "object",
              properties: %{
                "id" => %{type: "string"},
                "items" => %{
                  type: "array",
                  items: %{type: "object", properties: %{"count" => %{type: "integer"}}}
                }
              },
              required: ["id"]
            }
          }
        }
      },
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }
  end
end
