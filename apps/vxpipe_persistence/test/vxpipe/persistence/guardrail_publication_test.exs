defmodule Vxpipe.Persistence.GuardrailPublicationTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor
  alias Vxpipe.Persistence.{EctoStorage, UsageStore}
  alias Vxpipe.Calls.{Administration, ProviderCredentials}

  alias Vxpipe.Persistence.{
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore
  }

  setup do
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

    %{source: source, tenant: tenant, principal: principal, options: options}
  end

  test "publishing two agent policies pins the saved questions and Decisions selection to the call",
       %{source: source, tenant: tenant, principal: principal, options: options} do
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

  test "a closed guarded call publishes the rejected draft, dispatched feedback and reported usage from SQL",
       c do
    options = publication_options(c.options)
    {call, claim} = prepare_guarded_call(c, options)
    plan = call.plan
    [output_rule] = plan.participants["support"].guardrails.after_turn

    assert {:ok, archive} =
             ArchiveSupervisor.open(
               writer: {EctoStorage, options},
               maximum_pending_facts: 128,
               retry_delay_ms: 5,
               drain_timeout_ms: 2_000
             )

    archived = Process.monitor(archive.subscriber)
    configure_guarded_model()

    assert {:ok, room} =
             CallEngine.TestCallStartup.start_call(plan,
               archive_handoff: archive,
               credential_source: {Calls.ProviderCredentialSource, options}
             )

    assert {:ok, _} =
             Calls.mark_call_started(claim, room.incarnation_id, DateTime.utc_now(), options)

    identity = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      participant_id: plan.participants["caller"].participant_id,
      incarnation_id: room.incarnation_id,
      connection_id: "archive-fixture",
      deadline: DateTime.add(DateTime.utc_now(), 10, :second)
    ]

    assert {:ok, attach} = AttachConnection.new(identity)
    assert {:ok, attachment} = CallEngine.attach_connection(attach)
    CallEngine.TestCallStartup.await_ready(attachment)

    assert {:ok, input} =
             SendText.new(
               identity ++
                 [
                   correlation_id: "archive-turn",
                   content: "Permitted typed input.",
                   audio_response: false
                 ]
             )

    assert :ok = CallEngine.send_text(input)
    assert_receive {:test_agent_runtime_stream, model, _}, 2_000
    send_response(model, "Private rejected draft.")
    assert_receive {:test_agent_runtime_stream, repair, repair_request}, 2_000
    assert Enum.any?(repair_request.messages, &(&1.content =~ "Use the permitted reply."))
    send_response(repair, "Released reply.")

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnCompleted{correlation_id: "archive-turn"}},
                   2_000

    assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
    room_down = attachment.room_monitor
    assert_receive {:DOWN, ^room_down, :process, _, _}, 3_000
    assert_receive {:DOWN, ^archived, :process, _, :normal}, 3_000
    assert_receive {:vxpipe_call_details_published, _, publication, 1}, 3_000

    assert {:ok, %{state: :ended}} = Calls.fetch_call(call.tenant_key, call.id, options)
    assert {:ok, details} = Calls.fetch_call_details(c.principal, call.id, publication, options)
    doc = JSON.decode!(details.contents)
    rows = Enum.group_by(doc["decisions"], & &1["kind"], & &1["payload"])

    assert Enum.map(rows["decisions_evaluation"], &{&1["event"], &1["outcome"]}) ==
             [{"before_turn", "passed"}, {"after_turn", "blocked"}, {"after_turn", "passed"}]

    [input_check, blocked, replacement] = rows["decisions_evaluation"]
    assert input_check["source_turn_id"] == "archive-turn"
    assert blocked["candidate_attempt_id"] != replacement["candidate_attempt_id"]
    assert Enum.all?([blocked, replacement], &(&1["response_turn_id"] == "archive-turn"))
    assert blocked["checked_text"] == "Private rejected draft."
    assert replacement["checked_text"] == "Released reply."

    assert [%{"evaluation_id" => receipt_id, "question_ids" => [id]}] =
             rows["decisions_feedback_dispatched"]

    assert receipt_id == blocked["evaluation_id"] and id == output_rule.id

    assert Enum.any?(
             rows["decisions_question_result"],
             &(&1["evaluation_id"] == receipt_id and
                 &1["feedback_dispatched"] == true and
                 &1["feedback"] == "Use the permitted reply.")
           )

    assert Enum.map(rows["decisions_attempt"], & &1["attempt_id"]) |> Enum.uniq() |> length() == 3

    assert {:ok, observations} =
             UsageStore.fetch_usage_observations(Repo, call.tenant_key, call.id)

    decisions = Enum.filter(observations, &(&1.capability == :decisions))
    assert {:ok, settlement} = CallEngine.Usage.Settlement.derive(decisions)
    assert {:ok, 3} = CallEngine.Usage.Settlement.total(settlement, :requests)
    assert {:ok, 12} = CallEngine.Usage.Settlement.total(settlement, :tokens)
    transcript = JSON.encode!(doc["transcript"])
    assert transcript =~ "Permitted typed input." and transcript =~ "Released reply."
    refute transcript =~ "Private rejected draft."
    refute transcript =~ "Use the permitted reply."
  end

  defp publication_options(options) do
    alias Vxpipe.Persistence.{
      ArchiveStore,
      ArtifactStore,
      CallDetailsInspectionStore,
      CallDetailsPublicationStore,
      CallDetailsSource,
      TestPublicationArtifactWriter,
      TestPublicationClock
    }

    clock = start_supervised!({Agent, fn -> DateTime.add(DateTime.utc_now(), 60, :second) end})

    Keyword.merge(options,
      archive_repository: {ArchiveStore, Repo},
      artifact_repository: {ArtifactStore, Repo},
      usage_repository: {UsageStore, Repo},
      publication_enabled: true,
      publication_source: {CallDetailsSource, [repo: Repo]},
      publication_repository: {CallDetailsPublicationStore, Repo},
      publication_artifact_writer:
        {TestPublicationArtifactWriter, %{observer: self(), clock: clock}},
      publication_clock: {TestPublicationClock, clock},
      call_details_inspection_repository: {CallDetailsInspectionStore, Repo},
      observer: self()
    )
  end

  defp prepare_guarded_call(c, options) do
    assert {:ok, _} =
             ProviderCredentials.provision(
               c.tenant.key,
               "openai",
               "policy",
               "api_key",
               %{"api_key" => "synthetic-key"},
               options
             )

    question = %{
      question: "Is this permitted?",
      required_answer: "yes",
      response: "Use the permitted reply."
    }

    source =
      c.source
      |> Map.put(:schema_version, "20261128.01")
      |> Map.merge(%{
        media_policy: %{save_transcripts: true},
        wait_sounds: nil,
        opening_audio: nil
      })
      |> put_in([:defaults, :capabilities, :text_to_speech], %{provider: "morse", model: "morse"})
      |> put_in([:defaults, :capabilities, :decisions], %{
        provider: "openai",
        model: "gpt-6-luna",
        credential_name: "policy"
      })
      |> put_in([:participants, "support", :guardrails], %{
        before_turn: [question],
        after_turn: [question]
      })

    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source, options)

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, draft.revision, options)

    [route] = published.routes
    assert {:ok, call, token} = Calls.prepare_call(c.principal, route.key, %{}, options)
    scope = %{tenant_key: call.tenant_key, call_id: call.id, participant_key: route.key}
    assert {:ok, claim} = Calls.claim_join_token(token.secret, scope, options)
    {call, claim}
  end

  defp send_response(model, message) do
    text =
      JSON.encode!(%{
        type: "participant_message",
        participant_id: "support",
        agent_mode: "speaker",
        message: message
      })

    send(model, {:test_agent_runtime_delta, text})
    assert {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: text)
    send(model, {:test_agent_runtime_response, {:ok, response}})
  end

  defp configure_guarded_model do
    plug = fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))
      [question] = body["questions"]
      packet = JSON.decode!(body["input"])
      score = if packet["current"]["text"] == "Private rejected draft.", do: 0.1, else: 0.9

      Req.Test.json(conn, %{
        model: "gpt-6-luna",
        answers: [%{name: question["name"], type: "predicate", probability: score}],
        usage: %{input_tokens: 3, output_tokens: 1, total_tokens: 4}
      })
    end

    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    runtime =
      Keyword.merge(Keyword.fetch!(settings, :agent_runtime),
        fixture: {CallEngine.TestAgentRuntimeModelProvider, [owner: self()]},
        decisions_http_plug: plug
      )

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(settings, :agent_runtime, runtime)
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings) end)
  end
end
