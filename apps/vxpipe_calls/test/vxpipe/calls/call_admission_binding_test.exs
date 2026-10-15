defmodule Vxpipe.Calls.CallAdmissionBindingTest do
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

  test "binds an existing claim and retains its participant authority", c do
    assert {:ok, :admit, bound} = Calls.bind_call_admission(c.claim, "owner", c.options)
    assert bound == %{c.claim | call: %{c.claim.call | incarnation_id: "owner"}}
    assert {:ok, :admit, ^bound} = Calls.bind_call_admission(c.claim, "owner", c.options)

    assert {:error, :call_incarnation_mismatch} =
             Calls.bind_call_admission(c.claim, "other", c.options)

    assert :ok = Calls.release_admission(c.claim, c.options)
    assert {:ok, :cancel, ^bound} = Calls.bind_call_admission(c.claim, "owner", c.options)
  end

  test "rejects invalid ownership subjects and bounded incarnation identifiers before storage",
       c do
    options = [call_repository: {__MODULE__, :must_not_call}]

    for subject <- [nil, %{}, c.claim.call, %{c.claim | call: %{c.claim.call | id: nil}}] do
      assert {:error, :invalid_call_admission} =
               Calls.bind_call_admission(subject, "owner", options)
    end

    for incarnation <- [nil, "", String.duplicate("x", 129), "bad\nowner", <<255>>] do
      assert {:error, :invalid_call_admission} =
               Calls.bind_call_admission(c.claim, incarnation, options)
    end
  end

  test "sanitizes repository failures and rejects malformed or mismatched successful results",
       c do
    for result <- [
          :raise,
          :throw,
          :exit,
          {:error, "private-marker"},
          {:ok, :admit, %{}},
          {:ok, :maybe, c.claim},
          {:ok, :admit, %{c.claim | call: %{c.claim.call | incarnation_id: "different"}}}
        ] do
      assert {:error, :call_admission_unavailable} =
               Calls.bind_call_admission(c.claim, "owner", call_repository: {__MODULE__, result})
    end
  end

  def bind_call_admission(:must_not_call, _subject, _incarnation),
    do: flunk("invalid storage access")

  def bind_call_admission(:raise, _subject, _incarnation), do: raise("private-marker")
  def bind_call_admission(:throw, _subject, _incarnation), do: throw(:private)
  def bind_call_admission(:exit, _subject, _incarnation), do: exit(:private)
  def bind_call_admission(result, _subject, _incarnation), do: result
end
