defmodule Vxpipe.Persistence.Integration.CallHangupTransactionTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.{Admission, Call, JoinToken, Tenant}

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Hangup transaction", [:calls], options)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      stored = Repo.get_by!(Tenant, key: tenant.key)
      call_ids = from(c in Call, where: c.tenant_id == ^stored.id, select: c.id)
      Repo.delete_all(from(a in Admission, where: a.call_id in subquery(call_ids)))
      Repo.delete_all(from(c in Call, where: c.tenant_id == ^stored.id))
      Repo.delete!(stored)
      Sandbox.checkin(Repo)
    end)

    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)
    {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(actor, tenant.key, published.call_spec_id, %{}, nil, nil, options)

    {:ok, token} = Calls.issue_call_join_token(actor, tenant.key, call.id, nil, options)
    scope = %{tenant_key: tenant.key, call_id: call.id, participant_key: token.participant_key}
    %{actor: actor, tenant: tenant.key, call: call, token: token, options: options, scope: scope}
  end

  test "cancellation holds the call lock against token issuance and redemption until commit", c do
    {writer, monitor} = transaction_barrier(fn -> hangup(c) end)
    assert_receive {:transaction_locked, ^writer, {:ok, ended}}, 2_000
    assert ended.state == :ended

    assert_row_lock(fn ->
      Calls.issue_call_join_token(c.actor, c.tenant, c.call.id, nil, c.options)
    end)

    assert_row_lock(fn -> Calls.claim_join_token(c.token.secret, c.scope, c.options) end)
    commit(writer, monitor)

    assert {:error, :call_unavailable} =
             Calls.issue_call_join_token(c.actor, c.tenant, c.call.id, nil, c.options)

    assert {:error, :call_unavailable} =
             Calls.claim_join_token(c.token.secret, c.scope, c.options)

    assert Repo.get_by!(JoinToken, public_id: c.token.id).consumed_at == nil
    assert Repo.aggregate(from(a in Admission, where: a.call_id == ^stored_id(c)), :count) == 0
  end

  test "an admission that wins the call lock is retained as admitting when hangup follows", c do
    {writer, monitor} =
      transaction_barrier(fn -> Calls.claim_join_token(c.token.secret, c.scope, c.options) end)

    assert_receive {:transaction_locked, ^writer, {:ok, claim}}, 2_000
    assert claim.call.state == :admitting

    assert {:error, :blocked} =
             Repo.transaction(fn ->
               Repo.query!("SET LOCAL lock_timeout = '100ms'")
               assert {:error, :call_hangup_unavailable} = hangup(c)
               Repo.rollback(:blocked)
             end)

    commit(writer, monitor)
    assert {:ok, intent} = hangup(c)
    assert intent.state == :admitting
    assert intent.ended_at == nil and intent.terminal_reason == nil
    assert %DateTime{} = intent.hangup_requested_at
    assert %DateTime{} = Repo.get_by!(JoinToken, public_id: c.token.id).consumed_at
    assert Repo.aggregate(from(a in Admission, where: a.call_id == ^stored_id(c)), :count) == 1
  end

  defp assert_row_lock(operation) do
    assert {:error, :blocked} =
             Repo.transaction(fn ->
               Repo.query!("SET LOCAL lock_timeout = '100ms'")
               error = assert_raise Postgrex.Error, operation
               assert error.postgres.code == :lock_not_available
               Repo.rollback(:blocked)
             end)
  end

  defp transaction_barrier(operation) do
    observer = self()

    writer =
      start_supervised!(
        {Task,
         fn ->
           :ok = Sandbox.checkout(Repo, sandbox: false)

           result =
             Repo.transaction(fn ->
               result = operation.()
               send(observer, {:transaction_locked, self(), result})

               receive do
                 :commit -> :committed
               after
                 5_000 -> Repo.rollback(:test_timeout)
               end
             end)

           send(observer, {:writer_result, result})
           Sandbox.checkin(Repo)
         end}
      )

    {writer, Process.monitor(writer)}
  end

  defp commit(writer, monitor) do
    send(writer, :commit)
    assert_receive {:writer_result, {:ok, :committed}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}, 2_000
  end

  defp stored_id(c), do: Repo.get_by!(Call, public_id: c.call.id).id
  defp hangup(c), do: Calls.request_call_hangup(c.actor, c.tenant, c.call.id, c.options)

  defp source,
    do: %{
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
end
