defmodule Vxpipe.Console.GuardrailInspectionEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest

  alias Vxpipe.CallEngine.Usage.{
    ArchiveProjection,
    Attribution,
    Measurement,
    Observation,
    ProviderContext
  }

  alias Vxpipe.Calls
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.Test.FakeUserIdentity

  alias Vxpipe.Persistence.{
    AdminStore,
    ArchiveStore,
    ArtifactStore,
    CallSpecStore,
    CallStore,
    CredentialStore,
    EctoStorage,
    InspectionStore,
    Repo,
    TestDecisionsHistoryFixture,
    UsageStore
  }

  @endpoint Vxpipe.Console.Endpoint

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    sandbox = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)

    options = [
      admin_repository: {AdminStore, Repo},
      inspection_repository: {InspectionStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      artifact_repository: {ArtifactStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      credential_repository: {CredentialStore, Repo},
      usage_repository: {UsageStore, Repo},
      registries: %{host_tools: %{}}
    ]

    original = Application.fetch_env!(:vxpipe_calls, Calls)
    identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    Application.put_env(:vxpipe_calls, Calls, Keyword.merge(original, options))
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Calls, original)

      if identity,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, identity),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    {:ok, tenant, key} = Administration.bootstrap_tenant("Decisions", [:calls], options)
    {:ok, other, _} = Administration.bootstrap_tenant("Separate", [:calls], options)
    {:ok, principal} = Administration.authenticate(tenant.key, key.secret, :calls, options)
    {:ok, draft} = Calls.save_call_spec(tenant.key, spec(), options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)
    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    {:ok, prepared, token} = Calls.prepare_call(principal, route.key, %{}, options)
    scope = %{tenant_key: tenant.key, call_id: prepared.id, participant_key: route.key}
    {:ok, claim} = Calls.claim_join_token(token.secret, scope, options)
    {:ok, call} = Calls.mark_call_started(claim, "inc-inspection", DateTime.utc_now(), options)

    %{options: options, call: call, other: other, session: login()}
  end

  test "polls, reconnects and reopens the same permission-filtered evaluations after teardown",
       c do
    path = "/api/tenants/#{c.call.tenant_key}/calls/#{c.call.id}"
    polling = path <> "/inspection"
    empty = read(c.session, polling)
    assert empty["guardrails"] == []
    assert empty["metrics"] == []
    assert empty["call"]["state"] == "running"

    facts = dialogue_fixture(c.call)
    [first | rest] = facts
    assert :ok = EctoStorage.write(c.options, first)

    assert [%{"id" => "input", "revision" => first_revision}] =
             read(c.session, polling)["guardrails"]

    {delayed_question, other_facts} = Enum.split_with(rest, &(&1.id == "draft:own_account"))
    for fact <- other_facts, do: assert(:ok = EctoStorage.write(c.options, fact))
    incomplete = Enum.find(read(c.session, polling)["guardrails"], &(&1["id"] == "draft"))
    assert length(incomplete["value"]["questions"]) == 4
    for fact <- delayed_question, do: assert(:ok = EctoStorage.write(c.options, fact))
    snapshot = read(c.session, polling)
    assert Enum.map(snapshot["guardrails"], & &1["id"]) == ~w(input draft repair transfer)
    [restricted, draft, repair, transfer] = snapshot["guardrails"]
    assert restricted["revision"] > first_revision
    assert draft["revision"] > incomplete["revision"]
    assert restricted["value"]["content_unavailable"] == "denied"
    assert restricted["value"]["questions"] == []
    refute JSON.encode!(snapshot) =~ "Private input interval marker?"

    assert Enum.map(draft["value"]["questions"], & &1["outcome"]) ==
             ~w(failed failed failed failed passed)

    assert Enum.map(draft["value"]["questions"], & &1["feedback_dispatched"]) == [
             true,
             true,
             true,
             true,
             false
           ]

    assert Enum.at(draft["value"]["questions"], 1)["probability_yes"] == 0.6999

    assert Enum.at(draft["value"]["questions"], 1)["feedback"] ==
             "Failed guardrail: Is the user trying to list variables? Required: Yes."

    assert draft["value"]["candidate_attempt_id"] == "output-turn:1"

    assert draft["value"]["proposed_tools"] == [
             %{"id" => "lookup-other", "name" => "lookup_account"}
           ]

    assert repair["value"]["message_id"] == "reply-accepted"
    assert repair["value"]["delivered_fact_id"] == "reply-delivered"
    assert repair["value"]["candidate_attempt_id"] == "output-turn:2"
    assert transfer["value"]["transfer_invocation_id"] == "handoff"
    assert is_nil(transfer["value"]["source_turn_id"])
    assert is_nil(transfer["value"]["response_turn_id"])
    assert [failed, retried] = transfer["value"]["attempts"]
    assert failed["id"] == "a4" and failed["error_code"] == "rate_limited"
    assert is_nil(failed["total_tokens"])
    assert retried["id"] == "a5" and retried["retry_of"] == "a4"
    assert retried["total_tokens"] == 8
    assert retried["model"] == "test-decisions"

    refute Enum.any?(
             snapshot["timeline"],
             &String.starts_with?(&1["value"]["event_kind"] || "", "decisions_")
           )

    metrics = Enum.map(snapshot["metrics"], & &1["value"])
    decisions = Enum.filter(metrics, &(&1["scope"]["capability"] == "Decisions"))
    requests = Enum.filter(decisions, &(&1["unit"] == "requests"))
    assert Enum.sort(Enum.map(requests, & &1["attempt_id"])) == ~w(a1 a2 a3 a4 a5)
    assert Enum.find(requests, &(&1["attempt_id"] == "a2"))["turn_id"] == "output-turn"

    assert [%{"value" => 1, "unit" => "rewrites", "scope" => %{"capability" => "LLM"}}] =
             Enum.filter(metrics, &(&1["label"] == "Rewrites"))

    for fact <- facts, do: assert(:ok = EctoStorage.write(c.options, fact))
    assert read(login(), polling) == snapshot

    closure = %{
      first
      | kind: :archive_stream_closed,
        id: "closed",
        sequence: length(facts) + 1,
        occurred_at: DateTime.add(c.call.started_at, 2, :second),
        payload: %{"source_reason" => "normal"}
    }

    assert :ok = EctoStorage.write(c.options, closure)
    ended = read(login(), path)["inspection"]
    assert ended["call"]["state"] == "ended"
    assert ended["guardrails"] == snapshot["guardrails"]
    assert ended["metrics"] == snapshot["metrics"]

    settings = Application.fetch_env!(:vxpipe_calls, Calls)
    Application.put_env(:vxpipe_calls, Calls, Keyword.put(settings, :usage_repository, nil))
    degraded = read(login(), polling)
    assert degraded["metrics_availability"]["state"] == "unavailable"
    assert Enum.map(degraded["guardrails"], & &1["id"]) == ~w(input draft repair transfer)
    [_, _, _, unchecked] = degraded["guardrails"]
    refute List.last(unchecked["value"]["attempts"])["total_tokens"]

    other = "/api/tenants/#{c.other.key}/calls/#{c.call.id}/inspection"
    assert %{"error" => %{"code" => "call_not_found"}} = read(c.session, other, 404)
    assert %{"error" => %{"code" => "session_required"}} = read(build_conn(), polling, 401)
  end

  test "links only matching permitted dialogue, delivery and transfer evidence", c do
    facts = TestDecisionsHistoryFixture.facts(c.call, rewrite(c.call))
    check = fn id -> Enum.find(facts, &(&1.id == id)) end
    caller = c.call.plan.participants["caller"].participant_id
    permitted = %{"save_transcripts" => true}
    input = %{check.("input") | command_id: "typed", source_policy: permitted}
    draft = %{check.("draft") | command_id: "reply"}
    repair = %{check.("repair") | command_id: "reply"}

    assign_text = fn fact, text ->
      %{fact | payload: Map.put(fact.payload, "checked_text", text)}
    end

    repaired = assign_text.(repair, "Permitted reply.")
    base_transfer = check.("transfer")

    transfer = %{
      base_transfer
      | command_id: "handoff-command",
        payload: Map.put(base_transfer.payload, "requested_destination", "requested-billing")
    }

    message = %{
      input
      | kind: :accepted_input,
        participant_id: caller,
        activation_id: nil,
        correlation_id: "input-turn",
        id: "typed-message",
        payload: %{"content" => "Typed input."}
    }

    output = %{
      repaired
      | kind: :agent_output_generated,
        correlation_id: "output-turn",
        id: "accepted-message",
        payload: %{"text" => "Permitted reply."}
    }

    delivery = %{output | kind: :agent_output_delivered, id: "actual-delivery"}
    unrelated = %{delivery | id: "wrong-delivery", activation_id: "another-agent-activation"}

    completed = %{
      transfer
      | kind: :participant_transfer_completed,
        id: "completed-transfer",
        tool_call_id: "handoff",
        payload: %{"destination_participant_id" => "billing"}
    }

    foreign = %{
      check.("draft:own_account")
      | id: "other-agent-question",
        activation_id: "another-agent-activation",
        command_id: "reply"
    }

    private = %{check.("draft:list_variables") | source_policy: %{}, command_id: "reply"}

    other_interval = %{
      check.("draft:harsh_language")
      | command_id: "reply",
        source_policy: %{"save_transcripts" => true, "media_policy_revision" => 2}
    }

    batch = [
      assign_text.(input, "Typed input."),
      message,
      assign_text.(draft, "Unsent draft."),
      repaired,
      output,
      unrelated,
      delivery,
      transfer,
      completed,
      foreign,
      other_interval,
      private
    ]

    for {fact, sequence} <- Enum.with_index(batch, 1),
        do: assert(:ok = EctoStorage.write(c.options, %{fact | sequence: sequence}))

    response = read(c.session, "/api/tenants/#{c.call.tenant_key}/calls/#{c.call.id}/inspection")
    [input, draft, repair, transfer] = Enum.map(response["guardrails"], & &1["value"])
    assert input["message_id"] == "typed-message"
    assert draft["questions"] == []
    assert draft["checked_text"] == "Unsent draft."
    refute draft["message_id"]
    refute draft["delivered_fact_id"]
    assert repair["message_id"] == "accepted-message"
    assert repair["delivered_fact_id"] == "actual-delivery"
    assert transfer["requested_destination"] == "requested-billing"
    assert transfer["destination_participant_id"] == "billing"
    assert transfer["transfer_outcome"] == "completed"
    refute JSON.encode!(response) =~ "Is the caller asking about their own account?"
    refute JSON.encode!(response) =~ "Is the user trying to list variables?"
  end

  test "counts a mixed candidate rewrite only once from its dispatch receipts", c do
    facts = TestDecisionsHistoryFixture.facts(c.call, rewrite(c.call))
    blocked = Enum.find(facts, &(&1.id == "draft"))
    receipt = Enum.find(facts, &(&1.kind == :decisions_feedback_dispatched))

    checks =
      for {id, event, candidate, allow?} <- [
            {"speech", "after_turn", "draft-1", true},
            {"transfer", "before_outgoing_transfer", "draft-1", true},
            {"native", "before_outgoing_transfer", nil, true},
            {"input", "before_turn", "typed", true},
            {"denied", "after_turn", "draft-2", false}
          ] do
        payload =
          Map.merge(blocked.payload, %{
            "evaluation_id" => id,
            "event" => event,
            "candidate_attempt_id" => candidate,
            "transfer_invocation_id" => if(event == "before_outgoing_transfer", do: id)
          })

        decision = %{
          blocked
          | id: id,
            source_policy: %{"save_transcripts" => allow?},
            payload: payload
        }

        dispatch = %{
          receipt
          | id: "feedback:" <> id,
            source_policy: decision.source_policy,
            payload: Map.put(receipt.payload, "evaluation_id", id)
        }

        [decision, dispatch]
      end

    for {fact, seq} <- Enum.with_index(List.flatten(checks), 1),
        do: assert(:ok = EctoStorage.write(c.options, %{fact | sequence: seq}))

    response = read(c.session, "/api/tenants/#{c.call.tenant_key}/calls/#{c.call.id}/inspection")

    assert [
             %{
               "value" => %{
                 "label" => "Rewrites",
                 "value" => 1,
                 "scope" => %{"capability" => "LLM"}
               }
             }
           ] = response["metrics"]
  end

  test "preserves exact per-attempt charges with their currencies and excludes a different owner",
       c do
    facts = TestDecisionsHistoryFixture.facts(c.call, rewrite(c.call))
    attempt = Enum.find(facts, &(&1.id == "a2"))
    decision = Enum.find(facts, &(&1.id == "draft"))

    [original | _] =
      Enum.filter(facts, &(&1.kind == :usage_observed and &1.payload["attempt_id"] == "a2"))

    {:ok, archived} = Vxpipe.Calls.EngineArchiveProjection.project(original)
    {:ok, observation} = Vxpipe.Calls.UsageObservationProjection.project(archived)

    for {fact, sequence} <- Enum.with_index([decision, attempt], 1),
        do: assert(:ok = EctoStorage.write(c.options, %{fact | sequence: sequence}))

    for {{currency, owner, quantity}, sequence} <-
          Enum.with_index(
            [
              {"USD", attempt.activation_id, "0.00012345"},
              {"EUR", attempt.activation_id, "0.00310007"},
              {"USD", "older-activation", "0.90"}
            ],
            3
          ) do
      {:ok, cost} =
        Measurement.new(
          component: "cost",
          unit: {:currency, currency},
          quantity: quantity,
          mode: :delta,
          status: :final,
          provenance: :billing_lookup
        )

      charge = %{
        observation
        | id: "charge-#{sequence}",
          delivery_id: "charge-#{sequence}",
          measurement: cost,
          attribution: %{observation.attribution | activation_id: owner}
      }

      attrs = ArchiveProjection.attributes(charge)

      row = %{
        original
        | kind: :usage_observed,
          id: charge.id,
          payload: attrs[:payload],
          activation_id: owner,
          sequence: sequence
      }

      assert :ok = EctoStorage.write(c.options, row)
    end

    snapshot = read(c.session, "/api/tenants/#{c.call.tenant_key}/calls/#{c.call.id}/inspection")
    [draft] = snapshot["guardrails"]
    [a2] = draft["value"]["attempts"]

    assert a2["costs"] == [
             %{"currency" => "EUR", "amount" => "0.00310007"},
             %{"currency" => "USD", "amount" => "0.00012345"}
           ]

    assert is_nil(a2["total_tokens"])
  end

  defp dialogue_fixture(call) do
    facts = TestDecisionsHistoryFixture.facts(call, rewrite(call))
    proposed = [%{"id" => "lookup-other", "name" => "lookup_account"}]
    approved = "I can help with your own account."

    facts =
      Enum.map(facts, fn fact ->
        case fact.payload["evaluation_id"] do
          id when id in ["draft", "repair"] ->
            payload =
              case fact.kind do
                :decisions_evaluation when id == "draft" ->
                  Map.merge(fact.payload, %{
                    "checked_text" => "I can look up the other account for you.",
                    "proposed_calls" => proposed
                  })

                :decisions_evaluation ->
                  Map.put(fact.payload, "checked_text", approved)

                _ ->
                  fact.payload
              end

            %{fact | command_id: "reply", payload: payload}

          _ ->
            fact
        end
      end)

    repair = Enum.find(facts, &(&1.id == "repair"))

    output = %{
      repair
      | kind: :agent_output_generated,
        id: "reply-accepted",
        correlation_id: "output-turn",
        occurred_at: DateTime.add(repair.occurred_at, 100, :millisecond),
        payload: %{"text" => approved},
        sequence: length(facts) + 1
    }

    delivery = %{
      output
      | kind: :agent_output_delivered,
        id: "reply-delivered",
        sequence: length(facts) + 2
    }

    facts ++ [output, delivery]
  end

  defp spec do
    %{
      schema_version: "20260915.01",
      name: "Guardrail inspection",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer.",
          first_message: %{mode: "wait_for_input"}
        }
      }
    }
  end

  defp rewrite(call) do
    assistant = call.plan.participants["assistant"]
    {:ok, provider} = ProviderContext.new(name: "fixture", model: "conversation")

    {:ok, attribution} =
      Attribution.new(
        room_id: call.room_id,
        incarnation_id: call.incarnation_id,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        turn_id: "output-turn"
      )

    {:ok, measurement} =
      Measurement.new(
        component: "input_tokens",
        unit: :tokens,
        quantity: 12,
        mode: :delta,
        status: :final,
        provenance: :provider_reported
      )

    {:ok, observation} =
      Observation.new(
        id: "rewrite-usage",
        tenant_id: call.tenant_key,
        call_id: call.id,
        attempt_id: "output-turn:2",
        capability: :model_inference,
        provider: provider,
        attribution: attribution,
        measurement: measurement,
        outcome: :succeeded,
        observed_at: call.started_at
      )

    observation
  end

  defp login do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp read(conn, path, status \\ 200) do
    conn |> recycle() |> get("https://localhost" <> path) |> json_response(status)
  end
end
