defmodule Vxpipe.Persistence.ConfiguredSamplesTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Calls
  alias Vxpipe.Calls.ConfiguredSamples
  alias Vxpipe.Identity.Principal
  alias Vxpipe.Persistence.{Repo, CredentialStore, CallSpecStore, CallStore}

  setup do
    tenant =
      Repo.insert!(
        Vxpipe.Persistence.Schema.Tenant.changeset(%Vxpipe.Persistence.Schema.Tenant{}, %{
          key: "AAAAAAAAAAAAAAAA",
          name: "Configured sample"
        })
      )

    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    actor = %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["calls.write", "call_specs.write"]),
      assigned_tenants: %{tenant.key => :read_write},
      all_tenant_actions: MapSet.new()
    }

    config = %{
      tenant_key: tenant.key,
      call_spec: source(),
      initial_variables: %{"order" => %{"id" => "synthetic-order"}},
      transfer_participant: "support"
    }

    %{
      actor: actor,
      config: config,
      options: options,
      key_count: Repo.aggregate(Vxpipe.Persistence.Schema.ApiKey, :count)
    }
  end

  test "call-only actors reuse a publication but cannot create it; no hidden keys", c do
    caller = %{c.actor | grants: MapSet.new(["calls.write"])}
    assert {:error, :forbidden} = ConfiguredSamples.prepare(caller, c.config, c.options)
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 0
    assert {:ok, first} = ConfiguredSamples.prepare(c.actor, c.config, c.options)
    assert {:ok, second} = ConfiguredSamples.prepare(caller, c.config, c.options)
    refute first.call_id == second.call_id
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 1
    assert Repo.aggregate(Vxpipe.Persistence.Schema.ApiKey, :count) == c.key_count
    assert {:ok, call} = Calls.fetch_call(c.config.tenant_key, first.call_id, c.options)
    assert call.initial_variables == c.config.initial_variables
    assert call.state == :prepared
  end

  test "matching unpublished drafts resume only through the actual author's publication permission",
       c do
    caller = %{c.actor | grants: MapSet.new(["calls.write"])}

    assert {:ok, draft} =
             Calls.save_authorized_call_spec(
               c.actor,
               c.config.tenant_key,
               c.config.call_spec,
               c.options
             )

    assert {:error, :forbidden} = ConfiguredSamples.prepare(caller, c.config, c.options)

    assert {:error, :call_spec_not_published} =
             CallSpecStore.fetch_published_revision(Repo, c.config.tenant_key, draft.call_spec_id)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.Call, :count) == 0
    assert {:ok, token} = ConfiguredSamples.prepare(c.actor, c.config, c.options)
    assert {:ok, call} = Calls.fetch_call(c.config.tenant_key, token.call_id, c.options)
    assert call.call_spec_id == draft.call_spec_id
    assert call.call_spec_revision == draft.revision
    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpecRevision, :count) == 1
  end

  test "inherited platform services require actual authoring permission but allow published call-only reuse",
       c do
    {:ok, keyring} =
      Vxpipe.Persistence.CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})

    options =
      Keyword.put(
        c.options,
        :provider_credential_repository,
        {Vxpipe.Persistence.ProviderCredentialStore, [repo: Repo, keyring: keyring]}
      )

    assert {:ok, _} =
             Calls.ProviderCredentials.provision(
               :platform,
               "google",
               "default",
               "api_key",
               %{"api_key" => "synthetic-platform"},
               options
             )

    config =
      put_in(c.config, [:call_spec, :defaults, :capabilities, :model_inference], %{
        provider: "google",
        model: "gemini-3.5-flash-lite"
      })

    assert {:error, %{code: :provider_service_forbidden}} =
             ConfiguredSamples.prepare(c.actor, config, options)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpec, :count) == 0
    author = %{c.actor | grants: MapSet.put(c.actor.grants, "platform_services.read")}

    assert {:ok, draft} =
             Calls.save_authorized_call_spec(author, config.tenant_key, config.call_spec, options)

    assert {:error, %{code: :provider_service_forbidden}} =
             ConfiguredSamples.prepare(c.actor, config, options)

    assert {:error, :call_spec_not_published} =
             CallSpecStore.fetch_published_revision(Repo, config.tenant_key, draft.call_spec_id)

    assert {:ok, _} = ConfiguredSamples.prepare(author, config, options)
    caller = %{c.actor | grants: MapSet.new(["calls.write"])}
    assert {:ok, token} = ConfiguredSamples.prepare(caller, config, options)
    assert {:ok, call} = Calls.fetch_call(config.tenant_key, token.call_id, options)
    assert call.plan.credential_bindings[{"google", "default"}]["scope"] == "platform"
  end

  test "an ended prepared call cannot issue a transfer admission", c do
    assert {:ok, token} = ConfiguredSamples.prepare(c.actor, c.config, c.options)

    assert {:ok, ended} =
             Calls.request_call_hangup(c.actor, token.tenant_key, token.call_id, c.options)

    assert ended.state == :ended

    assert {:error, _} =
             ConfiguredSamples.transfer(
               c.actor,
               c.config,
               token.tenant_key,
               token.call_id,
               c.options
             )
  end

  test "edited or ambiguous configured sources are never overwritten", c do
    assert {:ok, token} = ConfiguredSamples.prepare(c.actor, c.config, c.options)
    assert {:ok, call} = Calls.fetch_call(c.config.tenant_key, token.call_id, c.options)
    changed = put_in(c.config.call_spec, [:participants, "assistant", :prompt], "Edited")

    assert {:ok, draft} =
             Calls.save_authorized_call_spec(
               c.actor,
               c.config.tenant_key,
               changed,
               Keyword.put(c.options, :call_spec_id, call.call_spec_id)
             )

    assert {:ok, _} =
             Calls.publish_authorized_call_spec(
               c.actor,
               c.config.tenant_key,
               draft.call_spec_id,
               draft.revision,
               c.options
             )

    assert {:error, :sample_spec_conflict} =
             ConfiguredSamples.prepare(c.actor, c.config, c.options)

    assert Repo.aggregate(Vxpipe.Persistence.Schema.CallSpecRevision, :count) == 2

    assert {:ok, _} =
             Calls.save_authorized_call_spec(
               c.actor,
               c.config.tenant_key,
               c.config.call_spec,
               c.options
             )

    assert {:error, :sample_spec_conflict} =
             ConfiguredSamples.prepare(c.actor, c.config, c.options)
  end

  test "transfer targets the selected pinned call and rejects foreign or cancellation-requested calls",
       c do
    caller = %{c.actor | grants: MapSet.new(["calls.write"])}
    assert {:ok, first} = ConfiguredSamples.prepare(c.actor, c.config, c.options)
    assert {:ok, second} = ConfiguredSamples.prepare(caller, c.config, c.options)

    for token <- [first, second] do
      scope = %{
        tenant_key: token.tenant_key,
        call_id: token.call_id,
        participant_key: token.participant_key
      }

      assert {:ok, claim} = Calls.claim_join_token(token.secret, scope, c.options)

      assert {:error, :token_already_claimed} =
               Calls.claim_join_token(token.secret, scope, c.options)

      assert {:ok, _} =
               Calls.mark_call_started(
                 claim,
                 "rinc_" <> token.call_id,
                 DateTime.utc_now(),
                 c.options
               )

      assert {:ok, transfer} =
               ConfiguredSamples.transfer(
                 caller,
                 c.config,
                 token.tenant_key,
                 token.call_id,
                 c.options
               )

      assert transfer.call_id == token.call_id
      assert transfer.participant_ref == "support"
    end

    assert {:error, :not_found} =
             ConfiguredSamples.transfer(
               caller,
               c.config,
               "BBBBBBBBBBBBBBBB",
               first.call_id,
               c.options
             )

    assert {:ok, _} =
             Calls.request_call_hangup(caller, first.tenant_key, first.call_id, c.options)

    assert {:error, _} =
             ConfiguredSamples.transfer(
               caller,
               c.config,
               first.tenant_key,
               first.call_id,
               c.options
             )

    assert {:ok, _} =
             ConfiguredSamples.transfer(
               caller,
               c.config,
               second.tenant_key,
               second.call_id,
               c.options
             )
  end

  defp source do
    %{
      schema_version: "20261004.01",
      name: "Development sample",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{type: "object", properties: %{"id" => %{type: "string"}}, required: ["id"]}
          }
        }
      },
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help.", transfers: ["support"]},
        "support" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "transfer"}
        }
      }
    }
  end
end
