defmodule Vxpipe.Persistence.GuardrailPublicationTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, ProviderCredentials}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore
  }

  test "publishing two agent policies pins the saved questions and Decisions selection to the call" do
    {:ok, keyring} = CredentialKeyring.new("v1", %{"v1" => :crypto.strong_rand_bytes(32)})

    options = [
      provider_credential_repository: {ProviderCredentialStore, [repo: Repo, keyring: keyring]},
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, issued} =
      Administration.bootstrap_tenant("Guardrails publication", [:calls], options)

    {:ok, principal} = Administration.authenticate(tenant.key, issued.secret, :calls, options)

    agent = %{
      type: "agent",
      prompt: "Help.",
      first_message: %{mode: "wait_for_input"},
      tools: %{},
      transfers: []
    }

    source = %{
      schema_version: "20261125.01",
      name: "Support",
      incoming_call: %{caller: "caller", handled_by: "support"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "support" => agent,
        "billing" => agent
      }
    }

    assert {:ok, original} = Calls.save_call_spec(tenant.key, source, options)
    id = original.call_spec_id
    assert {:ok, _} = Calls.publish_call_spec(tenant.key, id, 1, options)
    edit = Keyword.put(options, :call_spec_id, id)

    guarded =
      source
      |> Map.put(:schema_version, "20261128.01")
      |> put_in([:defaults, :capabilities, :decisions], %{
        provider: "openai",
        model: "gpt-6-luna",
        credential_name: "policy"
      })
      |> put_in([:participants, "support", :guardrails], %{
        before_outgoing_transfer: [
          %{
            question: "Is this about billing?",
            required_answer: "yes",
            probability_threshold: 0.75,
            response: "Ask which department is needed."
          }
        ]
      })
      |> put_in([:participants, "billing", :guardrails], %{
        before_outgoing_transfer: [
          %{question: "Is the caller requesting another account?", required_answer: "no"}
        ]
      })

    assert {:error,
            %{
              code: :provider_credential_unavailable,
              details: %{"path" => ["defaults", "capabilities", "decisions"]}
            }} =
             Calls.save_call_spec(tenant.key, guarded, edit)

    assert {:ok, _credential} =
             ProviderCredentials.provision(
               tenant.key,
               "openai",
               "policy",
               "api_key",
               %{"api_key" => "synthetic-decisions-key"},
               options
             )

    assert {:ok, draft} = Calls.save_call_spec(tenant.key, guarded, edit)
    assert {:ok, published} = Calls.publish_call_spec(tenant.key, id, 2, options)
    assert {:ok, fetched} = Calls.fetch_call_spec(tenant.key, id, 2, options)
    assert fetched.source == published.source
    assert fetched.source == draft.source
    [route] = published.routes
    assert {:ok, call, _token} = Calls.prepare_call(principal, route.key, %{}, options)
    assert {:ok, stored} = Calls.fetch_call(tenant.key, call.id, options)
    assert stored.call_spec_revision == 2

    assert %{provider: "openai", model: "gpt-6-luna", credential_name: "policy"} =
             stored.plan.decisions

    for {agent_key, answer, threshold, response} <- [
          {"support", :yes, 75, "Ask which department is needed."},
          {"billing", :no, 70, nil}
        ] do
      [saved] =
        get_in(fetched.source, [
          "participants",
          agent_key,
          "guardrails",
          "before_outgoing_transfer"
        ])

      policy = Map.fetch!(stored.plan.participants, agent_key).guardrails
      [compiled] = policy.before_outgoing_transfer
      assert compiled.id == saved["id"]
      assert compiled.question == saved["question"]
      assert compiled.required_answer == answer
      assert compiled.threshold_hundredths == threshold
      assert compiled.response == response
      assert policy.before_turn == [] and policy.after_turn == []
    end

    assert {:ok, old} = Calls.fetch_call_spec(tenant.key, id, 1, options)
    assert old.source_digest == original.source_digest
    assert old.source == original.source
    refute Map.has_key?(old.source["defaults"]["capabilities"], "decisions")
  end
end
