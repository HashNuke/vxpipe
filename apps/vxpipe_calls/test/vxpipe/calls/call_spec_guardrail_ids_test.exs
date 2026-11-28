defmodule Vxpipe.Calls.CallSpecGuardrailIdsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    Administration,
    CallSpecAuthoring,
    CallSpecs,
    InstallationOperator,
    Principal
  }

  alias Vxpipe.Calls.{TestGuardrailRevisionRepository, TestMemoryRepository}

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: TestMemoryRepository.credential_repository(repository),
      call_spec_repository: TestMemoryRepository.call_spec_repository(repository),
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, _issued} =
             Administration.bootstrap_tenant("Guardrail IDs", [:admin], options)

    [tenant: tenant, options: options, repository: repository]
  end

  test "creation assigns backend IDs and fetch returns them", %{tenant: tenant, options: options} do
    source = guarded_input()

    assert {:ok, draft} = CallSpecs.save(tenant.key, source, options)
    assert draft.validation_errors == []

    ids = question_ids(draft.source)
    assert length(ids) == 2
    assert Enum.all?(ids, &(&1 =~ ~r/\A[a-z][a-z0-9_]{0,63}\z/))
    assert Enum.uniq(ids) == ids

    assert {:ok, stored} = CallSpecs.fetch(tenant.key, draft.call_spec_id, 1, options)
    assert question_ids(stored.source) == ids
  end

  test "creation rejects a client-supplied ID", %{tenant: tenant, options: options} do
    source =
      put_in(guarded_input(), [:participants, "assistant", :guardrails, :before_turn], [
        %{id: "chosen_id", question: "Is this about your account?", required_answer: "yes"}
      ])

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, source, options)

    assert error.details["path"] == [
             "participants",
             "assistant",
             "guardrails",
             "before_turn",
             "0",
             "id"
           ]
  end

  test "update preserves returned IDs and assigns only new questions", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    ids = question_ids(first.source)
    assert length(ids) == 2

    # Round-trip the stored source (string keys) and add one new question without an ID.
    updated = add_question(first.source, "assistant", "after_turn", "Is this urgent?")

    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    assert {:ok, second} = CallSpecs.save(tenant.key, updated, update_options)

    new_ids = question_ids(second.source)
    assert length(new_ids) == 3
    assert Enum.take(new_ids, 2) == ids
    assert Enum.uniq(new_ids) == new_ids
  end

  test "update rejects unknown IDs", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)

    updated = put_question_id(first.source, "assistant", "before_turn", 0, "never_stored_id")
    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, updated, update_options)

    assert error.details["path"] == [
             "participants",
             "assistant",
             "guardrails",
             "before_turn",
             "0",
             "id"
           ]
  end

  test "update rejects foreign IDs from another participant", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, two_agent_input(), options)

    [assistant_id | _] = participant_question_ids(first.source, "assistant")

    updated = put_question_id(first.source, "helper", "before_turn", 0, assistant_id)
    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, updated, update_options)

    assert error.details["path"] == [
             "participants",
             "helper",
             "guardrails",
             "before_turn",
             "0",
             "id"
           ]
  end

  test "update rejects duplicate IDs", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    [first_id | _] = question_ids(first.source)

    updated =
      first.source
      |> add_question("assistant", "after_turn", "Is this urgent?")
      |> put_question_id("assistant", "after_turn", 1, first_id)

    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, updated, update_options)

    assert error.details["path"] == [
             "participants",
             "assistant",
             "guardrails",
             "after_turn",
             "1",
             "id"
           ]
  end

  test "stored IDs survive question edits and spec renames", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    [before_id, after_id] = question_ids(first.source)
    assert before_id =~ ~r/\A[a-z][a-z0-9_]{0,63}\z/
    assert after_id =~ ~r/\A[a-z][a-z0-9_]{0,63}\z/
    assert before_id != after_id

    renamed =
      first.source
      |> Map.put("name", "Renamed Guarded")
      |> edit_question_text(
        "assistant",
        "before_turn",
        0,
        "Is this about their own account? Edited"
      )

    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    assert {:ok, second} = CallSpecs.save(tenant.key, renamed, update_options)

    # Both stored IDs survive the edit/rename unchanged.
    assert question_ids(second.source) == [before_id, after_id]

    assert participant_question_ids(second.source, "assistant") |> Enum.sort() ==
             Enum.sort([before_id, after_id])
  end

  test "round-trip with two stored IDs preserves both", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    ids = question_ids(first.source)
    assert length(ids) == 2

    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    assert {:ok, second} = CallSpecs.save(tenant.key, first.source, update_options)
    assert question_ids(second.source) == ids
  end

  test "deleted IDs cannot be reused", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    [deleted_id, live_id] = question_ids(first.source)
    assert deleted_id != live_id

    # Revision 2 deletes the before_turn question, keeping only after_turn.
    without_before = delete_guardrail_event(first.source, "assistant", "before_turn")
    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    assert {:ok, second} = CallSpecs.save(tenant.key, without_before, update_options)
    assert question_ids(second.source) == [live_id]

    # Revision 3 attempts to reuse the deleted ID for a new question.
    reused =
      add_question_with_id(second.source, "assistant", "before_turn", "Reused?", deleted_id)

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, reused, update_options)

    assert error.details["path"] == [
             "participants",
             "assistant",
             "guardrails",
             "before_turn",
             "0",
             "id"
           ]
  end

  test "guardrail-free updates skip historical revision scans", %{
    tenant: tenant,
    options: options,
    repository: repository
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    assert {:ok, second} = CallSpecs.save(tenant.key, first.source, update_options)
    assert length(question_ids(second.source)) == 2

    counter = counter!()

    counting =
      {TestGuardrailRevisionRepository,
       %{agent: repository, after_read: fn -> Agent.update(counter, &(&1 + 1)) end}}

    counted_options = Keyword.merge(update_options, call_spec_repository: counting)

    # Guardrail-free save: strip all guardrails. Only preserve_direction reads
    # revision 1; the guardrail-ID path must not scan history.
    guardrail_free = remove_all_guardrails(second.source)
    refute Vxpipe.Calls.CallSpecGuardrailIds.has_guardrail_questions?(guardrail_free)

    assert {:ok, third} = CallSpecs.save(tenant.key, guardrail_free, counted_options)
    assert question_ids(third.source) == []
    assert Agent.get(counter, & &1) == 1
  end

  test "malformed participants or guardrails produce field errors without raising", %{
    tenant: tenant,
    options: options
  } do
    base = guarded_input()

    malformed_sources = [
      put_in(base, [:participants, "assistant"], "oops"),
      put_in(base, [:participants, "assistant", :guardrails], "oops"),
      put_in(base, [:participants, "assistant", :guardrails, :before_turn], %{}),
      put_in(base, [:participants, "assistant", :guardrails, :before_turn], ["oops"])
    ]

    for source <- malformed_sources do
      assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
               CallSpecs.save(tenant.key, source, options)
    end

    # String-keyed stored shapes must not raise in known_ids either.
    assert %{} == Vxpipe.Calls.CallSpecGuardrailIds.known_ids(%{"participants" => "oops"})

    assert MapSet.size(
             Vxpipe.Calls.CallSpecGuardrailIds.known_ids(%{
               "participants" => %{"assistant" => "oops"}
             })["assistant"]
           ) == 0
  end

  test "fixture carries valid TTS and Decisions capabilities", %{tenant: tenant, options: options} do
    assert {:ok, draft} = CallSpecs.save(tenant.key, guarded_input(), options)
    assert draft.validation_errors == []

    capabilities = get_in(draft.source, ["defaults", "capabilities"])
    assert get_in(capabilities, ["text_to_speech", "provider"]) == "morse"
    assert get_in(capabilities, ["decisions", "provider"]) == "fixture"
  end

  test "IDs are stable across an internal revision-conflict retry", %{
    tenant: tenant,
    options: options,
    repository: repository
  } do
    counter = counter!()

    generator = fn ->
      n = Agent.get_and_update(counter, fn n -> {n + 1, n + 1} end)
      "q_retry_#{String.pad_leading(Integer.to_string(n), 3, "0")}"
    end

    inserts = counter!()

    conflict_repository =
      {TestGuardrailRevisionRepository,
       %{
         agent: repository,
         conflict?: fn -> Agent.get_and_update(inserts, &{&1 == 0, &1 + 1}) end
       }}

    options =
      Keyword.merge(options,
        call_spec_repository: conflict_repository,
        guardrail_id_generator: generator
      )

    assert {:ok, draft} = CallSpecs.save(tenant.key, guarded_input(), options)
    ids = question_ids(draft.source)
    assert ids == ["q_retry_001", "q_retry_002"]
    assert Agent.get(counter, & &1) == 2
  end

  test "publication preserves IDs and authoring pathway assigns them", %{
    tenant: tenant,
    options: options
  } do
    principal = %Principal{
      tenant_key: tenant.key,
      api_key_id: "key",
      scopes: MapSet.new([:admin])
    }

    assert {:ok, draft} = CallSpecAuthoring.save(principal, tenant.key, guarded_input(), options)
    ids = question_ids(draft.source)
    assert length(ids) == 2

    assert {:ok, published} =
             CallSpecAuthoring.publish(principal, tenant.key, draft.call_spec_id, 1, options)

    assert question_ids(published.source) == ids

    # Installation operator pathway shares the same save behavior.
    authority = InstallationOperator.authority()

    assert {:ok, second} =
             CallSpecAuthoring.save(authority, tenant.key, guarded_input(), options)

    assert length(question_ids(second.source)) == 2
  end

  test "renaming a participant preserves saved question IDs", %{tenant: tenant, options: options} do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    ids = question_ids(first.source)
    assert length(ids) == 2

    renamed =
      first.source
      |> rename_participant("assistant", "assistant_renamed")
      |> put_in(["incoming_call", "handled_by"], "assistant_renamed")

    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    assert {:ok, second} = CallSpecs.save(tenant.key, renamed, update_options)
    assert question_ids(second.source) == ids
  end

  test "rejects merging, splitting or moving saved questions between participants", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, two_agent_input(), options)
    [assistant_id | _] = participant_question_ids(first.source, "assistant")
    [helper_id | _] = participant_question_ids(first.source, "helper")
    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    moved_to_existing = put_question_id(first.source, "helper", "before_turn", 0, assistant_id)

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
             CallSpecs.save(tenant.key, moved_to_existing, update_options)

    still_present =
      put_in(first.source, ["participants", "helper_new"], %{
        "type" => "agent",
        "guardrails" => %{
          "before_turn" => [
            %{"id" => assistant_id, "question" => "Copied?", "required_answer" => "yes"}
          ]
        }
      })

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
             CallSpecs.save(tenant.key, still_present, update_options)

    [before_id, after_id] = question_ids(first.source) |> Enum.take(2)
    split = rename_split(first.source, "assistant", ["split_a", "split_b"], [before_id, after_id])

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
             CallSpecs.save(tenant.key, split, update_options)

    combined =
      rename_combine(first.source, ["assistant", "helper"], "combined", [assistant_id, helper_id])

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
             CallSpecs.save(tenant.key, combined, update_options)
  end

  test "malformed entries within otherwise guarded source do not raise", %{
    tenant: tenant,
    options: options
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    base = first.source

    malformed = [
      put_in(base, ["participants", "helper"], "oops"),
      put_in(base, ["participants", "helper"], %{
        "type" => "agent",
        "guardrails" => "oops"
      }),
      put_in(base, ["participants", "helper"], %{
        "type" => "agent",
        "guardrails" => %{"before_turn" => %{"question" => "oops"}}
      }),
      put_in(base, ["participants", "helper"], %{
        "type" => "agent",
        "guardrails" => ["oops"]
      })
    ]

    for source <- malformed do
      assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec}} =
               CallSpecs.save(
                 tenant.key,
                 source,
                 Keyword.put(options, :call_spec_id, first.call_spec_id)
               )
    end
  end

  test "creation rejects explicit null IDs", %{tenant: tenant, options: options} do
    null_id_source =
      put_in(guarded_input(), [:participants, "assistant", :guardrails, :before_turn], [
        %{id: nil, question: "Is this about your account?", required_answer: "yes"}
      ])

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, null_id_source, options)

    assert error.details["path"] == [
             "participants",
             "assistant",
             "guardrails",
             "before_turn",
             "0",
             "id"
           ]

    assert error.details["reason"] =~ "must not include an ID"
  end

  test "retry verifies persisted references against winning revision", %{
    tenant: tenant,
    options: options,
    repository: repository
  } do
    assert {:ok, first} = CallSpecs.save(tenant.key, guarded_input(), options)
    [deleted_id, live_id] = question_ids(first.source)
    assert deleted_id != live_id
    winning_source = delete_guardrail_event(first.source, "assistant", "before_turn")
    assert question_ids(winning_source) == [live_id]
    loser_source = add_question(first.source, "assistant", "after_turn", "Loser new question?")
    update_options = Keyword.put(options, :call_spec_id, first.call_spec_id)
    gen_counter = counter!()

    generator = fn ->
      n = Agent.get_and_update(gen_counter, fn n -> {n + 1, n + 1} end)
      "q_loser_#{String.pad_leading(Integer.to_string(n), 3, "0")}"
    end

    fetch_counter = counter!()

    retry_repo =
      {TestGuardrailRevisionRepository,
       %{
         agent: repository,
         after_read: fn ->
           if Agent.get_and_update(fetch_counter, &{&1 == 0, &1 + 1}) do
             assert {:ok, %{revision: 2}} =
                      CallSpecs.save(tenant.key, winning_source, update_options)
           end
         end
       }}

    retry_options =
      Keyword.merge(update_options,
        call_spec_repository: retry_repo,
        guardrail_id_generator: generator
      )

    assert {:error, %Vxpipe.CallEngine.Error{code: :invalid_call_spec} = error} =
             CallSpecs.save(tenant.key, loser_source, retry_options)

    assert error.details["path"] == [
             "participants",
             "assistant",
             "guardrails",
             "before_turn",
             "0",
             "id"
           ]

    assert Agent.get(gen_counter, & &1) == 1
  end

  defp counter!, do: start_supervised!({Agent, fn -> 0 end}, id: make_ref())

  defp question_ids(source) do
    source
    |> get_participants()
    |> Enum.sort_by(fn {ref, _} -> ref end)
    |> Enum.flat_map(fn {_ref, participant} ->
      for event <- ["before_turn", "after_turn", "before_outgoing_transfer"],
          q <- get_questions(participant, event),
          do: get_id(q)
    end)
  end

  defp participant_question_ids(source, ref) do
    participant =
      get_in(source, ["participants", ref]) || get_in(source, [:participants, ref]) || %{}

    for event <- ["before_turn", "after_turn", "before_outgoing_transfer"],
        q <- get_questions(participant, event),
        do: get_id(q)
  end

  defp get_participants(%{"participants" => participants}) when is_map(participants),
    do: participants

  defp get_participants(%{participants: participants}) when is_map(participants), do: participants
  defp get_participants(_), do: %{}

  defp get_questions(participant, event) do
    guardrails = Map.get(participant, "guardrails") || Map.get(participant, :guardrails) || %{}

    case Map.get(guardrails, event) || Map.get(guardrails, String.to_atom(event)) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp get_id(%{"id" => id}), do: id
  defp get_id(%{id: id}), do: id
  defp get_id(_), do: nil

  defp add_question(source, participant_ref, event, question_text) do
    question = %{"question" => question_text, "required_answer" => "yes"}
    path = ["participants", participant_ref, "guardrails", event]
    existing = get_in(source, path) || []
    put_in(source, path, existing ++ [question])
  end

  defp add_question_with_id(source, participant_ref, event, question_text, id) do
    question = %{"id" => id, "question" => question_text, "required_answer" => "yes"}
    path = ["participants", participant_ref, "guardrails", event]
    existing = get_in(source, path) || []
    put_in(source, path, existing ++ [question])
  end

  defp edit_question_text(source, participant_ref, event, index, text) do
    path = ["participants", participant_ref, "guardrails", event]
    questions = get_in(source, path) || []

    updated =
      List.replace_at(questions, index, Map.put(Enum.at(questions, index), "question", text))

    put_in(source, path, updated)
  end

  defp delete_guardrail_event(source, participant_ref, event) do
    put_in(source, ["participants", participant_ref, "guardrails", event], [])
  end

  defp remove_all_guardrails(source) do
    participants = get_in(source, ["participants"]) || %{}

    updated =
      Map.new(participants, fn
        {ref, participant} when is_map(participant) ->
          {ref, Map.delete(participant, "guardrails")}

        entry ->
          entry
      end)

    put_in(source, ["participants"], updated)
  end

  defp put_question_id(source, participant_ref, event, index, id) do
    path = ["participants", participant_ref, "guardrails", event]
    questions = get_in(source, path) || []
    updated = List.replace_at(questions, index, Map.put(Enum.at(questions, index), "id", id))
    put_in(source, path, updated)
  end

  defp rename_participant(source, old_ref, new_ref) do
    participants = get_in(source, ["participants"])
    participant = get_in(source, ["participants", old_ref])
    updated = participants |> Map.delete(old_ref) |> Map.put(new_ref, participant)
    put_in(source, ["participants"], updated)
  end

  defp rename_split(source, old_ref, [new_a, new_b], [id_a, id_b]) do
    participants = get_in(source, ["participants"])
    old = get_in(source, ["participants", old_ref])
    old_guard = Map.get(old, "guardrails", %{})
    before_q = old_guard |> Map.get("before_turn", []) |> Enum.at(0) |> Map.put("id", id_a)
    after_q = old_guard |> Map.get("after_turn", []) |> Enum.at(0) |> Map.put("id", id_b)
    a = %{"type" => "agent", "guardrails" => %{"before_turn" => [before_q]}}
    b = %{"type" => "agent", "guardrails" => %{"before_turn" => [after_q]}}

    updated =
      participants |> Map.delete(old_ref) |> Map.put(new_a, a) |> Map.put(new_b, b)

    put_in(source, ["participants"], updated)
  end

  defp rename_combine(source, old_refs, new_ref, ids) do
    participants = get_in(source, ["participants"])

    questions =
      Enum.map(ids, fn id ->
        %{"id" => id, "question" => "Combined?", "required_answer" => "yes"}
      end)

    combined = %{"type" => "agent", "guardrails" => %{"before_turn" => questions}}

    updated =
      Enum.reduce(old_refs, participants, fn ref, acc -> Map.delete(acc, ref) end)
      |> Map.put(new_ref, combined)

    put_in(source, ["participants"], updated)
  end

  defp guarded_input do
    %{
      schema_version: "20261128.01",
      name: "Guarded",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{
        capabilities: %{
          model_inference: %{provider: "fixture", model: "test"},
          text_to_speech: %{provider: "morse", model: "morse"},
          decisions: %{provider: "fixture", model: "fixture"}
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: [],
          guardrails: %{
            before_turn: [
              %{question: "Is the caller asking about their own account?", required_answer: "yes"}
            ],
            after_turn: [
              %{
                question: "Does this disclose another account?",
                required_answer: "no",
                probability_threshold: 0.75,
                response: "I can only discuss your own account."
              }
            ]
          }
        }
      }
    }
  end

  defp two_agent_input do
    base = guarded_input()

    helper = %{
      type: "agent",
      prompt: "Help.",
      first_message: %{mode: "wait_for_input"},
      tools: %{},
      transfers: [],
      guardrails: %{
        before_turn: [%{question: "Is the helper needed?", required_answer: "yes"}]
      }
    }

    put_in(base, [:participants, "helper"], helper)
  end
end
