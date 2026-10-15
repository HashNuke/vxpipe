defmodule Vxpipe.Calls.CallCleanupCompletionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository}

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      call_spec_repository: TestMemoryRepository.call_spec_repository(repository),
      call_repository: TestMemoryRepository.call_repository(repository),
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Binding", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    source = %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }

    {:ok, draft} = Calls.save_call_spec(tenant.key, source, options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(actor, tenant.key, published.call_spec_id, %{}, nil, nil, options)

    {:ok, token} = Calls.issue_call_join_token(actor, tenant.key, call.id, nil, options)

    {:ok, claim} =
      Calls.claim_join_token(
        token.secret,
        %{tenant_key: tenant.key, call_id: call.id, participant_key: token.participant_key},
        options
      )

    %{claim: claim, options: options}
  end

  @completed ~U[2026-10-15 20:00:00.000Z]

  test "requests publication after storage returns and on repeated completion", c do
    result = %{
      c.claim.call
      | incarnation_id: "owner",
        gateway_cleanup_required: true,
        gateway_cleanup_completed_at: @completed
    }

    options = [
      call_repository: {__MODULE__, {self(), {:ok, result}}},
      publication_enabled: true,
      publication_finalizer_starter: Vxpipe.Calls.TestPublicationFinalizerStarter,
      publication_trigger_observer: self()
    ]

    for _retry <- 1..2 do
      assert {:ok, ^result} = Calls.complete_call_cleanup(cleanup_binding(c), @completed, options)
      assert_receive :completion_stored
      assert_receive {:publication_finalization_requested, tenant, id}
      assert tenant == result.tenant_key and id == result.id
    end
  end

  test "rejects malformed input before persistence and never publishes failed or mismatched completion",
       c do
    for changed <- [
          nil,
          %{},
          Map.put(cleanup_binding(c), :reason, :api_hangup),
          Map.put(cleanup_binding(c), :incarnation_id, "")
        ] do
      assert {:error, :invalid_call_cleanup} =
               Calls.complete_call_cleanup(changed, @completed,
                 call_repository: {__MODULE__, :must_not_call}
               )
    end

    for failure <- [
          :raise,
          :exit,
          {:error, "private"},
          {:ok, c.claim.call},
          {:ok,
           %{
             c.claim.call
             | incarnation_id: "foreign",
               gateway_cleanup_required: true,
               gateway_cleanup_completed_at: @completed
           }}
        ] do
      assert {:error, :call_cleanup_unavailable} =
               Calls.complete_call_cleanup(cleanup_binding(c), @completed,
                 call_repository: {__MODULE__, failure},
                 publication_enabled: true,
                 publication_finalizer_starter: Vxpipe.Calls.TestPublicationFinalizerStarter,
                 publication_trigger_observer: self()
               )

      refute_received {:publication_finalization_requested, _, _}
    end
  end

  defp cleanup_binding(c),
    do: %{
      tenant_key: c.claim.call.tenant_key,
      call_id: c.claim.call.id,
      room_id: c.claim.call.room_id,
      incarnation_id: "owner"
    }

  def complete_call_cleanup(:must_not_call, _, _), do: flunk("unexpected storage")
  def complete_call_cleanup(:raise, _, _), do: raise("private")
  def complete_call_cleanup(:exit, _, _), do: exit(:private)

  def complete_call_cleanup({observer, result}, _, _) when is_pid(observer) do
    send(observer, :completion_stored)
    result
  end

  def complete_call_cleanup(result, _, _), do: result
end
