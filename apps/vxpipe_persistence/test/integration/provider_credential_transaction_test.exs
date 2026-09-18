defmodule Vxpipe.Persistence.Integration.ProviderCredentialTransactionTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials}

  alias Vxpipe.Persistence.{
    CredentialKeyring,
    CredentialStore,
    CallSpecStore,
    ProviderCredentialStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.{ProviderCredential, Tenant}

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    {:ok, keyring} =
      CredentialKeyring.new("race-key", %{"race-key" => :crypto.strong_rand_bytes(32)})

    context = [repo: Repo, keyring: keyring]

    options = [
      credential_repository: {CredentialStore, Repo},
      provider_credential_repository: {ProviderCredentialStore, context},
      call_spec_repository: {CallSpecStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, _issued} =
      Administration.bootstrap_tenant("Transaction test tenant", [:calls], options)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
      Sandbox.checkin(Repo)
    end)

    {:ok, credential} =
      ProviderCredentials.provision(
        tenant.key,
        "google",
        "default",
        "api_key",
        %{"api_key" => "synthetic-transaction-key"},
        options
      )

    [tenant: tenant, credential: credential, context: context, options: options]
  end

  test "holds the credential through the authorized write against a separate revoking transaction",
       ctx do
    observer = self()
    requirements = [%{provider: "google", name: "default", path: ["model_inference"]}]
    {:ok, initial} = Calls.save_call_spec(ctx.tenant.key, source(), ctx.options)

    routes =
      Enum.map(initial.routes, &%{&1 | key: Vxpipe.Calls.PublicId.uuid(), call_spec_revision: 2})

    revision = %{initial | revision: 2, routes: routes}

    writer =
      db_task(fn ->
        result =
          ProviderCredentialStore.with_active(ctx.context, ctx.tenant.key, requirements, fn ->
            send(observer, {:credential_write_held, self()})

            receive do
              :write -> CallSpecStore.insert_revision(Repo, ctx.tenant.key, revision, routes)
            after
              2_000 -> {:error, :test_write_timeout}
            end
          end)

        send(observer, {:credential_write_result, result})
      end)

    assert_receive {:credential_write_held, ^writer}, 1_000

    db_task(fn ->
      result =
        try do
          Repo.transaction(fn ->
            Repo.query!("SET LOCAL lock_timeout = '100ms'")
            revoke(ctx.credential.id)
          end)
        rescue
          error in Postgrex.Error -> {:error, error.postgres.code}
        end

      send(observer, {:concurrent_revoke_result, result})
    end)

    assert_receive {:concurrent_revoke_result, {:error, :lock_not_available}}, 1_000
    send(writer, :write)
    assert_receive {:credential_write_result, {:ok, draft}}, 1_000
    assert draft.validation_errors == []
    assert {1, _} = revoke(ctx.credential.id)

    assert {:error, %{code: :provider_credential_unavailable}} =
             Calls.publish_call_spec(
               ctx.tenant.key,
               draft.call_spec_id,
               draft.revision,
               ctx.options
             )

    assert [route] = draft.routes

    assert {:error, :route_unavailable} =
             Calls.resolve_participant_route(ctx.tenant.key, route.key, ctx.options)
  end

  defp db_task(operation) do
    start_supervised!(
      {Task,
       fn ->
         :ok = Sandbox.checkout(Repo, sandbox: false)

         try do
           operation.()
         after
           Sandbox.checkin(Repo)
         end
       end},
      id: {Task, make_ref()}
    )
  end

  defp revoke(id) do
    Repo.update_all(from(c in ProviderCredential, where: c.public_id == ^id),
      set: [status: "revoked"]
    )
  end

  defp source do
    %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      wait_sounds: nil,
      defaults: %{
        capabilities: %{model_inference: %{provider: "google", model: "gemini-3.5-flash-lite"}}
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
