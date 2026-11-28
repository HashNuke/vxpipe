defmodule Vxpipe.CallEngine.Guardrails.EmissionPublicationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.DecisionsFact

  alias Vxpipe.CallEngine.Archive.{Handoff, Port, Recorder}
  alias Vxpipe.CallEngine.CallSpec.Guardrails
  alias Vxpipe.CallEngine.Guardrails.{Emission, Participant}
  alias Vxpipe.CallEngine.RoomAuthority.DecisionsPublication

  setup do
    {:ok, policy} =
      Guardrails.new(
        %{
          "before_turn" => [
            %{
              "id" => "private_request",
              "question" => "Is the caller asking about their own account?",
              "required_answer" => "yes"
            },
            %{
              "id" => "other_account",
              "question" => "Is the issue about a different account?",
              "required_answer" => "no",
              "response" => "Ask which account the caller needs."
            }
          ]
        },
        []
      )

    %{policy: policy}
  end

  defp start_participant(policy, adapter, emission, options \\ []) do
    tasks = start_supervised!(Task.Supervisor)

    start_supervised!(
      {Participant,
       [
         policy: policy,
         adapter: adapter,
         request_supervisor: tasks,
         participant_id: "agent-1",
         activation_id: "act-1",
         policy_revision: 3,
         policy_digest: "sha256:" <> String.duplicate("a", 64),
         selected_provider: "openai",
         selected_model: "gpt-6-luna",
         tenant_id: "t1",
         call_id: "c1",
         room_id: "r1",
         incarnation_id: "i1",
         on_emit: emission
       ] ++ options}
    )
  end

  defp recorder_with_handoff do
    subscriber = self()
    handoff = Handoff.new(subscriber, 128)

    port =
      Port.new(
        handoff,
        nil,
        %{tenant_id: "t1", call_id: "c1", room_id: "r1", incarnation_id: "i1"},
        %{"revision" => 0}
      )

    recorder = %Recorder{port: port, participant_activations: %{"agent-1" => "act-1"}}
    {recorder, handoff}
  end

  defp trusted_state(recorder) do
    %{
      archive_recorder: recorder,
      snapshot: %{tenant_id: "t1", room_id: "r1", incarnation_id: "i1", call_id: "c1"},
      transcript_router: nil
    }
  end

  defp drain_facts(acc \\ []) do
    receive do
      {:vxpipe_archive, :fact, _token, fact} -> drain_facts([fact | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp finished_event(overrides \\ %{}) do
    Map.merge(
      %{
        phase: :finished,
        ordinal: 1,
        started_at_ms: System.monotonic_time(:millisecond),
        ended_at_ms: System.monotonic_time(:millisecond),
        duration_ms: 10,
        outcome: :succeeded,
        error_code: nil,
        model: "gpt-6-luna",
        request_id: "req-1",
        usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15},
        probabilities: %{"private_request" => 0.9, "other_account" => 0.1}
      },
      overrides
    )
  end

  test "replaying a dispatch acknowledgement emits one receipt with only failed question IDs", %{
    policy: policy
  } do
    owner = self()

    adapter = fn request ->
      request.on_attempt.(finished_event())
      {:ok, %{scores: %{"private_request" => 0.1, "other_account" => 0.1}}}
    end

    participant = start_participant(policy, adapter, &send(owner, {:reported, &1}))

    assert {:blocked, [_line], confirm} =
             Vxpipe.CallEngine.Guardrails.CheckClient.check_with_receipt(
               participant,
               :before_turn,
               "source-turn",
               %{},
               System.monotonic_time(:millisecond) + 1000
             )

    assert_receive {:reported, %{outcome: :blocked, evaluation_id: evaluation}}
    refute_received {:reported, %{kind: :decisions_feedback_dispatched}}
    confirm.()
    confirm.()

    assert_receive {:reported,
                    %{
                      kind: :decisions_feedback_dispatched,
                      evaluation_id: ^evaluation,
                      question_ids: ["private_request"]
                    } = receipt}

    refute Map.has_key?(receipt, :feedback)
    refute Map.has_key?(receipt, :questions)
    refute_received {:reported, _}
    {recorder, _handoff} = recorder_with_handoff()

    assert DecisionsPublication.record(trusted_state(recorder), %{
             kind: receipt.kind,
             evaluation_id: evaluation
           }) == trusted_state(recorder)
  end

  test "each retry retains only its own returned identifiers and physical timing", %{
    policy: policy
  } do
    owner = self()

    adapter = fn request ->
      start = System.monotonic_time(:millisecond)

      request.on_attempt.(
        finished_event(%{
          started_at_ms: start,
          ended_at_ms: start + 4,
          duration_ms: 4,
          outcome: :failed,
          error_code: :rate_limited,
          model: nil,
          request_id: nil,
          usage: :unknown
        })
      )

      request.on_attempt.(
        finished_event(%{
          ordinal: 2,
          started_at_ms: start + 8,
          ended_at_ms: start + 11,
          duration_ms: 3,
          model: "returned-model",
          request_id: "retry-request"
        })
      )

      {:ok,
       %{
         scores: %{"private_request" => 1, "other_account" => 0},
         model: "returned-model",
         request_id: "retry-request"
       }}
    end

    participant = start_participant(policy, adapter, &send(owner, {:reported, &1}))

    assert :passed =
             Participant.check(
               participant,
               :before_turn,
               "retry",
               %{},
               System.monotonic_time(:millisecond) + 2000
             )

    assert_received {:reported, report}
    [first, second] = report.attempts

    [first_request, second_request] =
      Enum.filter(report.usage_observations, &(&1.measurement.component == "requests"))

    assert first_request.provider.model == nil
    assert first_request.provider.request_id == nil
    assert second_request.provider.model == "returned-model"
    assert second_request.provider.request_id == "retry-request"
    assert DateTime.diff(second.started_at, first.started_at, :millisecond) == 8
    assert DateTime.diff(first.ended_at, first.started_at, :millisecond) == 4
    assert DateTime.diff(second.ended_at, second.started_at, :millisecond) == 3
    assert first_request.observed_at == first.ended_at
    assert second_request.observed_at == second.ended_at
  end

  test "successful live check publishes evaluation, questions and actual attempts with usage", %{
    policy: policy
  } do
    parent = self()

    adapter = fn request ->
      send(parent, {:adapter_request, request})
      assert is_function(request[:on_attempt], 1)
      assert is_binary(request[:evaluation_id])

      request[:on_attempt].(finished_event())

      {:ok,
       %{
         scores: %{"private_request" => 0.9, "other_account" => 0.1},
         model: "gpt-6-luna",
         request_id: "req-1",
         usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15}
       }}
    end

    emission = fn report -> send(parent, {:emitted, report}) end
    participant = start_participant(policy, adapter, emission)

    evidence = %{
      "text" => "hello",
      "correlation" => %{
        "source_participant_id" => "caller-1",
        "source_turn_id" => "turn-1",
        "command_id" => "cmd-1"
      }
    }

    assert :passed =
             Participant.check(
               participant,
               :before_turn,
               "proposal-1",
               evidence,
               System.monotonic_time(:millisecond) + 2_000
             )

    assert_received {:emitted, report}
    assert_received {:adapter_request, %{evaluation_id: evaluation_id}}
    assert report.evaluation_id == evaluation_id
    assert report.evaluation_id =~ "deval_"
    assert report.event == :before_turn
    assert report.outcome == :passed
    assert report.participant_id == "agent-1"
    assert report.activation_id == "act-1"
    assert report.source_participant_id == "caller-1"
    assert report.policy_revision == 3
    assert report.policy_digest =~ "sha256:"
    # Actual physical attempt only, no synthesis.
    assert length(report.attempts) == 1
    [attempt] = report.attempts
    assert attempt.attempt_id =~ "datt_"
    assert attempt.outcome == :succeeded
    assert attempt.provider == "openai"
    assert attempt.model == "gpt-6-luna"
    assert report.actual_model == "gpt-6-luna"
    assert report.feedback_dispatched == false

    {recorder, _handoff} = recorder_with_handoff()
    state = trusted_state(recorder)

    # Scope must match trusted room; report carries tenant/call/room.
    state =
      DecisionsPublication.record(state, %{
        report
        | tenant_id: "t1",
          call_id: "c1",
          room_id: "r1",
          incarnation_id: "i1"
      })

    facts = drain_facts()

    kinds = Enum.map(facts, & &1.kind) |> Enum.sort()
    assert :decisions_evaluation in kinds
    assert :decisions_question_result in kinds
    assert :decisions_attempt in kinds
    assert :usage_observed in kinds

    for fact <- facts do
      if fact.kind in [:decisions_evaluation, :decisions_question_result, :decisions_attempt] do
        assert :ok == DecisionsFact.validate(fact.kind, fact.payload)
      end
    end

    # Unknown privacy defaults to unknown marker, not denied, and still redacts text.
    question_facts = Enum.filter(facts, &(&1.kind == :decisions_question_result))
    assert length(question_facts) == 2

    for fact <- question_facts do
      assert fact.payload["content_unavailable"] == %{"reason" => "unknown"}
    end

    # No public event projection: publication never sends {:vxpipe_event, _}.
    refute_received {:vxpipe_event, _}

    # Duplicate delivery by IDs: recording the same report twice keeps stable IDs.
    state =
      DecisionsPublication.record(state, %{
        report
        | tenant_id: "t1",
          call_id: "c1",
          room_id: "r1",
          incarnation_id: "i1"
      })

    facts2 = drain_facts()
    assert length(facts2) == length(facts)
    assert Enum.map(facts2, & &1.id) == Enum.map(facts, & &1.id)

    _ = state
  end

  test "a partial provider batch preserves trustworthy question evidence without feedback", %{
    policy: policy
  } do
    parent = self()

    adapter = fn request ->
      request.on_attempt.(
        finished_event(%{
          outcome: :failed,
          error_code: :invalid_result,
          usage: :unknown,
          probabilities: %{"other_account" => 0.94}
        })
      )

      {:error, :invalid_result}
    end

    participant = start_participant(policy, adapter, &send(parent, {:emitted, &1}))

    assert {:error, :invalid_result} =
             Participant.check(
               participant,
               :before_turn,
               "partial-answer",
               %{"text" => "Synthetic"},
               System.monotonic_time(:millisecond) + 2_000
             )

    assert_received {:emitted, report}
    assert report.outcome == :error

    assert [%{outcome: :unavailable}, %{outcome: :failed, probability_yes: 0.94}] =
             report.outcomes

    assert report.feedback == []
    assert report.feedback_dispatched == false
    assert report.actual_model == "gpt-6-luna"
    assert report.actual_request_id == "req-1"
    assert {:ok, facts} = Emission.question_facts(report, %{})
    assert Enum.all?(facts, fn {_kind, attrs} -> is_nil(attrs[:payload]["feedback"]) end)
  end

  test "one reported counter makes one token observation and keeps an attributable late correction",
       %{policy: policy} do
    parent = self()

    adapter = fn request ->
      request.on_attempt.(finished_event(%{usage: %{input_tokens: 0}}))
      {:ok, %{scores: %{"private_request" => 0.9, "other_account" => 0.1}}}
    end

    participant = start_participant(policy, adapter, &send(parent, {:emitted, &1}))

    assert :passed =
             Participant.check(
               participant,
               :before_turn,
               "partial-usage",
               %{"text" => "Synthetic"},
               System.monotonic_time(:millisecond) + 2_000
             )

    assert_received {:emitted, report}
    measured = Enum.map(report.usage_observations, & &1.measurement.component)
    assert Enum.sort(measured) == ["input_tokens", "requests"]
    assert {:ok, [correction]} = Emission.late_usage(report, %{output_tokens: 3})
    assert correction.measurement.component == "output_tokens"
    assert correction.measurement.included_in == nil
    assert correction.attempt_id == hd(report.attempts).attempt_id
  end

  test "blocked check preserves per-question results and does not fabricate usage", %{
    policy: policy
  } do
    parent = self()

    adapter = fn request ->
      request[:on_attempt].(
        finished_event(%{
          usage: :unknown,
          probabilities: %{"private_request" => 0.1, "other_account" => 0.9},
          request_id: "req-blocked-1",
          model: "gpt-6-luna"
        })
      )

      {:ok,
       %{
         scores: %{"private_request" => 0.1, "other_account" => 0.9},
         model: "gpt-6-luna",
         usage: :unknown
       }}
    end

    emission = fn report -> send(parent, {:emitted, report}) end
    participant = start_participant(policy, adapter, emission)

    assert {:blocked, lines} =
             Participant.check(
               participant,
               :before_turn,
               "p2",
               %{"text" => "x"},
               System.monotonic_time(:millisecond) + 2_000
             )

    assert length(lines) == 2
    assert_received {:emitted, report}
    assert report.outcome == :blocked
    # A computed block alone never claims model dispatch.
    assert report.feedback_dispatched == false
    # Unknown provider tokens stay unknown: no token components invented.
    refute Enum.any?(report.usage_observations, fn obs ->
             obs.measurement != nil and
               obs.measurement.component in ["input_tokens", "output_tokens"]
           end)

    # Requests usage is still recorded exactly once per submitted actual attempt.
    assert Enum.any?(report.usage_observations, fn obs ->
             obs.measurement != nil and obs.measurement.component == "requests" and
               obs.measurement.quantity == 1
           end)
  end

  test "cancelled live check emits cancelled outcome and late usage does not reopen the gate", %{
    policy: policy
  } do
    parent = self()

    adapter = fn _request ->
      receive do
        :response -> {:ok, %{scores: %{}}}
      end
    end

    emission = fn report -> send(parent, {:emitted, report}) end
    participant = start_participant(policy, adapter, emission)

    assert {:error, :timeout} =
             Participant.check(
               participant,
               :before_turn,
               "p3",
               %{"text" => "x"},
               System.monotonic_time(:millisecond) + 20
             )

    assert_received {:emitted, report}
    assert report.outcome == :cancelled
    assert report.attempts == []
    assert report.usage_observations == []

    {recorder, _handoff} = recorder_with_handoff()
    state = trusted_state(recorder)

    state =
      DecisionsPublication.record(state, %{
        report
        | tenant_id: "t1",
          call_id: "c1",
          room_id: "r1",
          incarnation_id: "i1"
      })

    facts = drain_facts()
    assert Enum.any?(facts, &(&1.kind == :decisions_evaluation))
    assert Enum.any?(facts, &(&1.payload["outcome"] == "cancelled"))

    assert {:error, :unknown_attempt} = Emission.late_usage(report, %{input_tokens: 7})
    _ = state
  end

  test "a submitted attempt survives owner cancellation and receives only its own late usage", %{
    policy: policy
  } do
    parent = self()

    adapter = fn request ->
      request.on_attempt.(%{
        phase: :started,
        ordinal: 1,
        started_at_ms: System.monotonic_time(:millisecond)
      })

      send(parent, {:submitted, self()})

      receive do
        :provider_response ->
          event = finished_event(%{usage: %{output_tokens: 3}})
          request.on_attempt.(event)
          request.on_attempt.(event)
          {:ok, %{scores: %{"private_request" => 0.9, "other_account" => 0.1}}}
      end
    end

    participant =
      start_participant(policy, adapter, &send(parent, {:terminal, &1}),
        on_late_usage: &send(parent, {:late, &1})
      )

    owner =
      spawn(fn ->
        Participant.check(
          participant,
          :before_turn,
          "p-late",
          %{"source_turn_id" => "input-7"},
          System.monotonic_time(:millisecond) + 2_000
        )
      end)

    assert_receive {:submitted, transport}
    _ = :sys.get_state(participant)
    Process.exit(owner, :kill)
    monitor = Process.monitor(transport)

    assert_receive {:terminal,
                    %{outcome: :cancelled, attempts: [attempt], usage_observations: [request]}}

    assert request.measurement.component == "requests"
    assert request.attempt_id == attempt.attempt_id
    assert attempt.outcome == :cancelled
    assert attempt.usage == :unknown
    send(transport, :provider_response)
    assert_receive {:late, [correction]}
    assert correction.attempt_id == attempt.attempt_id
    assert correction.measurement.component == "output_tokens"
    assert correction.measurement.quantity == 3
    assert correction.attribution.turn_id == "input-7"
    assert_receive {:DOWN, ^monitor, :process, ^transport, _}
    _ = :sys.get_state(participant)
    refute_received {:late, _}
    refute_received {:terminal, _}
  end

  test "retiring admission cancels its live caller and accepts a scoped metering correction", %{
    policy: policy
  } do
    parent = self()
    admission = start_supervised!({Agent, fn -> :open end})

    adapter = fn request ->
      :ok =
        request.on_attempt.(%{
          phase: :started,
          ordinal: 1,
          started_at_ms: System.monotonic_time(:millisecond)
        })

      send(parent, {:http_submitted, self()})

      receive do
        :late_failure ->
          request.on_attempt.(
            finished_event(%{
              outcome: :failed,
              error_code: :invalid_result,
              usage: %{input_tokens: 5}
            })
          )

          {:error, :invalid_result}
      end
    end

    checks =
      start_participant(policy, adapter, &send(parent, {:cancelled_report, &1}),
        admission_owner: admission,
        on_late_usage: &send(parent, {:meter, &1})
      )

    result =
      Task.async(fn ->
        Participant.check(
          checks,
          :before_turn,
          "turn",
          %{},
          System.monotonic_time(:millisecond) + 2_000
        )
      end)

    assert_receive {:http_submitted, wire}
    stopped = Process.monitor(checks)
    assert :ok = stop_supervised(Agent)
    assert {:error, :cancelled} = Task.await(result)

    assert_receive {:cancelled_report,
                    %{
                      outcome: :cancelled,
                      error_code: :cancelled,
                      attempts: [%{attempt_id: attempt, outcome: :cancelled}],
                      usage_observations: [request]
                    }}

    assert request.measurement.component == "requests"

    assert {:error, :cancelled} =
             Participant.check(
               checks,
               :before_turn,
               "new-turn",
               %{},
               System.monotonic_time(:millisecond) + 1_000
             )

    send(wire, :late_failure)
    assert_receive {:meter, [correction]}
    assert correction.attempt_id == attempt
    assert correction.outcome == :failed
    assert_receive {:DOWN, ^stopped, :process, ^checks, :normal}

    {recorder, _} = recorder_with_handoff()
    state = trusted_state(recorder)

    invalid = [
      Map.from_struct(correction),
      request,
      %{correction | tenant_id: "other"},
      %{correction | call_id: "other"},
      %{correction | attribution: %{correction.attribution | room_id: "other"}},
      %{correction | attribution: %{correction.attribution | incarnation_id: "other"}}
    ]

    DecisionsPublication.record_usage(state, invalid ++ [correction])

    assert [
             %{
               kind: :usage_observed,
               payload: %{"outcome" => "failed", "measurement" => %{"quantity" => 5}}
             }
           ] = drain_facts()

    refute_received {:cancelled_report, _}
  end

  test "unknown privacy defaults to unknown, untrusted scope and stale activation drop", %{
    policy: policy
  } do
    parent = self()

    adapter = fn request ->
      request[:on_attempt].(finished_event(%{request_id: "req-unknown-1", usage: :unknown}))

      {:ok,
       %{
         scores: %{"private_request" => 0.9, "other_account" => 0.1},
         model: "gpt-6-luna",
         usage: :unknown
       }}
    end

    emission = fn report -> send(parent, {:emitted, report}) end
    participant = start_participant(policy, adapter, emission)

    assert :passed =
             Participant.check(
               participant,
               :before_turn,
               "p4",
               %{"text" => "secret"},
               System.monotonic_time(:millisecond) + 2_000
             )

    assert_received {:emitted, report}
    base = %{report | tenant_id: "t1", call_id: "c1", room_id: "r1", incarnation_id: "i1"}

    {recorder, _handoff} = recorder_with_handoff()
    state = trusted_state(recorder)

    _ = DecisionsPublication.record(state, base)
    facts = drain_facts()
    question_facts = Enum.filter(facts, &(&1.kind == :decisions_question_result))
    assert length(question_facts) == 2

    for fact <- question_facts do
      assert fact.payload["content_unavailable"] == %{"reason" => "unknown"}
      assert fact.payload["probability_yes"] == nil
    end

    # Untrusted scope drops.
    evil = %{base | tenant_id: "evil"}
    seq_before = DecisionsPublication.record(state, evil).archive_recorder.port.next_sequence
    assert seq_before == state.archive_recorder.port.next_sequence
    assert drain_facts() == []

    # Stale activation drops.
    stale = %{base | activation_id: "stale-act"}
    seq2 = DecisionsPublication.record(state, stale).archive_recorder.port.next_sequence
    assert seq2 == state.archive_recorder.port.next_sequence
    assert drain_facts() == []

    for incarnation <- [nil, "another-incarnation"] do
      projected = DecisionsPublication.record(state, %{base | incarnation_id: incarnation})

      assert projected.archive_recorder.port.next_sequence ==
               state.archive_recorder.port.next_sequence

      refute_received {:vxpipe_archive, :fact, _, _}
    end
  end
end
