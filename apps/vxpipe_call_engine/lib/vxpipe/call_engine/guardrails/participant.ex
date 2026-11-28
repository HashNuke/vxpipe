defmodule Vxpipe.CallEngine.Guardrails.Participant do
  @moduledoc "Owns in-flight guardrail checks for one participant activation."
  use GenServer

  alias Vxpipe.CallEngine.CallSpec.Guardrails
  alias Vxpipe.CallEngine.Guardrails.{Emission, Evidence}
  alias Vxpipe.CallEngine.TranscriptRouter
  alias Vxpipe.CallEngine.TranscriptRouter.Projection

  @events [:before_turn, :after_turn, :before_outgoing_transfer]
  @derive {Inspect, only: [:timeout_ms]}
  defstruct [
    :policy,
    :adapter,
    :supervisor,
    :timeout_ms,
    :participant_id,
    :activation_id,
    :policy_revision,
    :policy_digest,
    :selected_provider,
    :selected_model,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :enforce_input_route?,
    :on_emit,
    :on_late_usage,
    :admission_owner,
    :admission_monitor,
    retired?: false,
    pending: %{},
    late_reports: %{}
  ]

  def activation_child(activation_id, request_supervisor, settings) do
    name = Vxpipe.CallEngine.AgentActivationSupervisor.child_ref(activation_id, :guardrails)
    settings = Keyword.merge(settings, name: name, request_supervisor: request_supervisor)

    module =
      if is_binary(settings[:incarnation_id]),
        do: Vxpipe.CallEngine.Guardrails.Activation,
        else: __MODULE__

    Supervisor.child_spec({module, settings}, id: :guardrails, restart: :transient)
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def check(server, event, proposal, evidence, deadline)
      when event in @events and is_map(evidence) and is_integer(deadline) do
    remaining = max(deadline - now(), 0)
    GenServer.call(server, {:check, event, proposal, evidence, deadline}, remaining + 100)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, {:shutdown, _} -> {:error, :cancelled}
    :exit, _ -> {:error, :unavailable}
  end

  def input_permitted?(server, source, revision) do
    GenServer.call(server, {:input_permitted, source, revision}, 500)
  catch
    :exit, _ -> false
  end

  @impl true
  def init(options) do
    owner = Keyword.get(options, :admission_owner)

    {:ok,
     %__MODULE__{
       policy: Keyword.fetch!(options, :policy),
       admission_owner: owner,
       admission_monitor: if(owner, do: Process.monitor(owner)),
       adapter: Keyword.fetch!(options, :adapter),
       supervisor: Keyword.fetch!(options, :request_supervisor),
       timeout_ms:
         Keyword.get_lazy(
           options,
           :timeout_ms,
           &Vxpipe.CallEngine.Guardrails.Deadline.evaluation_timeout_ms/0
         ),
       participant_id: Keyword.get(options, :participant_id),
       activation_id: Keyword.get(options, :activation_id),
       policy_revision: Keyword.get(options, :policy_revision, 0),
       policy_digest:
         Keyword.get_lazy(options, :policy_digest, fn ->
           Guardrails.digest(Keyword.fetch!(options, :policy))
         end),
       selected_provider: Keyword.get(options, :selected_provider),
       selected_model: Keyword.get(options, :selected_model),
       tenant_id: Keyword.get(options, :tenant_id),
       call_id: Keyword.get(options, :call_id),
       room_id: Keyword.get(options, :room_id),
       incarnation_id: Keyword.get(options, :incarnation_id),
       enforce_input_route?: Keyword.get(options, :enforce_input_route?, false),
       on_emit: normalize_emit(Keyword.get(options, :on_emit)),
       on_late_usage: normalize_emit(Keyword.get(options, :on_late_usage))
     }}
  end

  @impl true
  def handle_cast({:from_activation, from, request}, state) do
    case handle_call(request, from, state) do
      {:reply, result, next} ->
        GenServer.reply(from, result)
        {:noreply, next}

      {:noreply, next} ->
        {:noreply, next}
    end
  end

  @impl true
  def handle_call({:check, _, _, _, _}, _from, %{retired?: true} = state),
    do: {:reply, {:error, :cancelled}, state}

  @impl true
  def handle_call({:input_permitted, source, revision}, _from, state) do
    {:reply, admission_open?(state) and input_route?(state, source, revision), state}
  end

  def handle_call({:check, event, proposal, evidence, deadline}, from, state) do
    {return_receipt?, evidence} = Map.pop(evidence, :return_feedback_receipt, false)
    questions = questions(state.policy, event)
    deadline = min(deadline, now() + state.timeout_ms)
    correlation = extract_correlation(evidence, event, proposal)

    cond do
      not admission_open?(state) ->
        {:reply, {:error, :cancelled}, state}

      not permitted_for_check?(state, event, correlation) ->
        emit_cancelled_from_entry(
          state,
          evaluation_entry(event, proposal, correlation, questions),
          :stale
        )

        {:reply, {:error, :stale}, state}

      questions == [] ->
        {:reply, :passed, state}

      deadline <= now() ->
        emit_cancelled_from_entry(
          state,
          evaluation_entry(event, proposal, correlation, questions),
          :timeout
        )

        {:reply, {:error, :timeout}, state}

      busy?(state.pending, event, proposal) ->
        {:reply, {:error, :busy}, state}

      true ->
        correlation = pin_source_interval(correlation, event, state)
        entry = evaluation_entry(event, proposal, correlation, questions)
        entry = Map.put(entry, :checked_text, archived_text(state, entry, evidence["text"]))
        evaluation_id = entry.evaluation_id

        participant_pid = self()

        request = %{
          evaluation_id: evaluation_id,
          event: event,
          proposal: proposal,
          evidence: evidence,
          deadline: deadline,
          questions: Enum.map(questions, &Map.take(&1, [:id, :question])),
          on_attempt: fn
            %{phase: :started} = event ->
              GenServer.call(participant_pid, {:submit, evaluation_id, event}, state.timeout_ms)

            %{phase: :finished} = event ->
              send(participant_pid, {:decisions_attempt_event, evaluation_id, event})
              :ok
          end
        }

        adapter = state.adapter

        task =
          Task.Supervisor.async_nolink(state.supervisor, fn ->
            run(adapter, request, questions)
          end)

        {caller, _tag} = from

        entry =
          Map.merge(entry, %{
            return_receipt?: return_receipt?,
            from: from,
            pid: task.pid,
            owner_ref: Process.monitor(caller),
            deadline: deadline,
            timer: Process.send_after(self(), {:expired, task.ref}, max(deadline - now(), 0))
          })

        {:noreply, %{state | pending: Map.put(state.pending, task.ref, entry)}}
    end
  end

  def handle_call({:submit, id, %{ordinal: ordinal} = event}, _from, state)
      when ordinal in 1..2 do
    case Enum.find(state.pending, fn {_ref, entry} -> entry.evaluation_id == id end) do
      {ref, entry} ->
        if admission_open?(state) and entry.deadline > now() and
             not Map.has_key?(entry.attempt_ids, ordinal) and
             permitted_for_check?(state, entry.event, entry.correlation) do
          {:reply, :ok, store_event(state, ref, entry, event)}
        else
          {:reply, {:error, :cancelled}, state}
        end

      nil ->
        {:reply, {:error, :cancelled}, state}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{admission_monitor: monitor, admission_owner: owner} = state
      ) do
    continue_drain(retire_admission(state))
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    state = if admission_open?(state), do: state, else: retire_admission(state)

    case Map.fetch(state.pending, ref) do
      {:ok, entry} ->
        reply =
          if permitted_for_check?(state, entry.event, entry.correlation) do
            late? = now() >= entry.deadline
            report = emit_terminal(state, entry, result, late?)

            if late?,
              do: {:error, :timeout},
              else: feedback_reply(detailed_reply(result), entry, report, state)
          else
            emit_cancelled_from_entry(state, entry, :stale)
            {:error, :stale}
          end

        GenServer.reply(entry.from, reply)
        {:noreply, remove(state, ref, entry)}

      :error ->
        continue_drain(forget_late(state, ref))
    end
  end

  def handle_info({:decisions_attempt_event, evaluation_id, event_map}, state)
      when is_binary(evaluation_id) and is_map(event_map) do
    case Enum.find(state.pending, fn {_ref, entry} -> entry.evaluation_id == evaluation_id end) do
      {ref, entry} ->
        {:noreply, store_event(state, ref, entry, event_map)}

      nil ->
        {:noreply, record_late_event(state, evaluation_id, event_map)}
    end
  end

  def handle_info({:stop_late, ref}, state) do
    if drain = state.late_reports[ref], do: Process.exit(drain.pid, :kill)
    continue_drain(forget_late(state, ref))
  end

  def handle_info({:expired, ref}, state) do
    case Map.fetch(state.pending, ref) do
      {:ok, entry} ->
        GenServer.reply(entry.from, {:error, :timeout})
        {:noreply, cancel_check(state, ref, entry, :timeout)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.fetch(state.pending, ref) do
      {:ok, entry} ->
        emit_cancelled_from_entry(state, entry, :unavailable)
        GenServer.reply(entry.from, {:error, :unavailable})
        {:noreply, remove(state, ref, entry)}

      :error ->
        case Enum.find(state.pending, fn {_ref, entry} -> entry.owner_ref == ref end) do
          {worker_ref, entry} ->
            reason = if now() >= entry.deadline, do: :timeout, else: :cancelled
            {:noreply, cancel_check(state, worker_ref, entry, reason)}

          nil ->
            drain_ref =
              Enum.find_value(state.late_reports, fn {task_ref, drain} ->
                if drain.monitor == ref, do: task_ref
              end)

            continue_drain(forget_late(state, drain_ref))
        end
    end
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _value} when key in [:state, :message, :reason, :log] -> {key, :redacted}
      entry -> entry
    end)
  end

  defp retire_admission(state) do
    Enum.reduce(state.pending, %{state | retired?: true}, fn {ref, entry}, acc ->
      GenServer.reply(entry.from, {:error, :cancelled})
      cancel_check(acc, ref, entry, :cancelled)
    end)
  end

  defp admission_open?(%{admission_owner: nil}), do: true
  defp admission_open?(%{admission_owner: owner}), do: Process.alive?(owner)

  defp continue_drain(%{retired?: true, late_reports: late} = state) when map_size(late) == 0,
    do: {:stop, :normal, state}

  defp continue_drain(state), do: {:noreply, state}

  defp questions(policy, :before_turn), do: policy.before_turn
  defp questions(policy, :after_turn), do: policy.after_turn
  defp questions(policy, :before_outgoing_transfer), do: policy.before_outgoing_transfer

  defp busy?(pending, event, proposal) do
    Enum.any?(pending, fn {_ref, entry} ->
      entry.proposal != proposal or entry.event == event or :before_turn in [entry.event, event]
    end)
  end

  defp normalize_emit(fun) when is_function(fun, 1), do: fun
  defp normalize_emit(_), do: nil

  defp feedback_reply(
         {:blocked, lines},
         %{return_receipt?: true},
         %{outcome: :blocked} = report,
         %{on_emit: emit}
       )
       when is_function(emit, 1) do
    receipt = Emission.feedback_receipt(report)
    once = :atomics.new(1, [])

    {:blocked, lines,
     fn ->
       if :atomics.compare_exchange(once, 1, 0, 1) == :ok,
         do: emit.(Map.put(receipt, :dispatched_at, DateTime.utc_now(:millisecond)))
     end}
  end

  defp feedback_reply(verdict, _entry, _report, _state), do: verdict

  defp detailed_reply({:passed, _, _, _}), do: :passed

  defp detailed_reply({:blocked, _, evaluation, _}),
    do: {:blocked, Guardrails.feedback(evaluation)}

  defp detailed_reply({status, code, _, _}) when status in [:cancelled, :error],
    do: {:error, code}

  defp run(adapter, request, questions) do
    case adapter.(request) do
      {:ok, %{scores: scores} = result} when is_map(scores) ->
        case Guardrails.evaluate(questions, scores) do
          {:ok, evaluation} -> {evaluation.status, nil, evaluation, result}
          {:error, evaluation} -> {:error, :invalid_result, evaluation, result}
        end

      {:error, reason} when is_atom(reason) ->
        worker_error(reason, questions)

      _ ->
        worker_error(:invalid_result, questions)
    end
  rescue
    _ -> worker_error(:unavailable, questions)
  catch
    _, _ -> worker_error(:unavailable, questions)
  end

  defp worker_error(reason, questions) do
    {error_outcome(reason), error_code(reason), %{outcomes: unavailable_outcomes(questions)}, %{}}
  end

  defp error_outcome(:cancelled), do: :cancelled
  defp error_outcome(:stale), do: :cancelled
  defp error_outcome(_), do: :error

  defp error_code(reason)
       when reason in [
              :timeout,
              :unavailable,
              :unauthorized,
              :transport_error,
              :rate_limited,
              :invalid_result,
              :refused,
              :oversized,
              :retry_exhausted,
              :stale
            ],
       do: reason

  defp error_code(:cancelled), do: :cancelled
  defp error_code(_), do: :invalid_result

  defp unavailable_outcomes(questions) do
    Enum.map(questions, fn question ->
      %{
        question_id: question.id,
        probability_yes: nil,
        inferred_answer: nil,
        outcome: :unavailable
      }
    end)
  end

  # --- emission ---

  defp evaluation_entry(event, proposal, correlation, questions) do
    %{
      event: event,
      proposal: proposal,
      correlation: correlation,
      questions: questions,
      evaluation_id: Emission.new_evaluation_id(),
      started_wall: DateTime.utc_now(:millisecond),
      started_mono: now(),
      attempt_events: [],
      attempt_ids: %{}
    }
  end

  defp emit_terminal(state, entry, {outcome, error, evaluation, result}, late?) do
    if late? do
      emit_cancelled_from_entry(state, entry, :timeout)
    else
      last_attempt = Enum.find(entry.attempt_events, &finished_attempt_event?/1) || %{}
      evaluation = evaluation_evidence(outcome, entry.questions, last_attempt, evaluation)

      emit_report(state, entry, %{
        outcome: outcome,
        error_code: error,
        outcomes: normalize_outcomes(entry.questions, evaluation.outcomes),
        feedback: if(outcome == :blocked, do: Guardrails.feedback(evaluation), else: []),
        actual_provider: actual_provider(result),
        actual_model: actual_model(result) || event_model(last_attempt),
        actual_request_id: actual_request_id(result) || event_request_id(last_attempt)
      })
    end
  end

  defp evaluation_evidence(:error, questions, %{probabilities: partial}, _evaluation)
       when is_map(partial) do
    {_status, evaluation} = Guardrails.evaluate(questions, partial)
    evaluation
  end

  defp evaluation_evidence(_outcome, _questions, _attempt, evaluation), do: evaluation

  defp emit_cancelled_from_entry(state, entry, reason) do
    emit_report(state, entry, %{
      outcome: :cancelled,
      error_code: error_code(reason),
      outcomes: unavailable_outcomes(entry.questions)
    })
  end

  defp archived_text(
         %{incarnation_id: incarnation} = state,
         %{event: event, correlation: link},
         text
       )
       when is_binary(incarnation) and event in [:before_turn, :after_turn] and is_binary(text) and
              byte_size(text) in 1..8192 do
    source =
      if event == :after_turn,
        do: link.source_participant_id || state.participant_id,
        else: link.source_participant_id

    router = TranscriptRouter.whereis(incarnation)
    interval = Evidence.storage_policy(router, state, source, link.source_policy_revision)
    if interval["save_transcripts"] == true and String.valid?(text), do: text
  end

  defp archived_text(_, _, _), do: nil

  defp emit_report(state, entry, result) do
    finished_at = DateTime.utc_now(:millisecond)
    identity = Map.take(state, [:tenant_id, :call_id, :room_id, :incarnation_id])

    base =
      Map.take(state, [
        :participant_id,
        :activation_id,
        :policy_digest,
        :selected_provider,
        :selected_model
      ])

    attributes =
      base
      |> Map.merge(identity)
      |> Map.merge(entry.correlation)
      |> Map.merge(result)
      |> Map.merge(%{
        evaluation_id: entry.evaluation_id,
        event: entry.event,
        checked_text:
          if(result.outcome != :cancelled,
            do: archived_text(state, entry, Map.get(entry, :checked_text))
          ),
        policy_revision: state.policy_revision || 0,
        questions: entry.questions,
        attempts: actual_attempts(state, entry, entry.started_wall, finished_at),
        started_at: entry.started_wall,
        ended_at: finished_at,
        duration_ms: max(now() - entry.started_mono, 0)
      })

    {:ok, report} = Emission.build_report(attributes)
    {:ok, observations} = Emission.usage_observations(report, identity)
    report = %{report | usage_observations: observations}
    dispatch(state, report)
    report
  end

  defp dispatch(%{on_emit: nil}, _report), do: :ok

  defp dispatch(%{on_emit: emit}, report) when is_function(emit, 1) do
    try do
      emit.(report)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
  end

  defp store_event(state, ref, entry, %{ordinal: ordinal} = event) when ordinal in 1..2 do
    ids = Map.put_new_lazy(entry.attempt_ids, ordinal, &Emission.new_attempt_id/0)
    updated = %{entry | attempt_ids: ids, attempt_events: [event | entry.attempt_events]}
    %{state | pending: Map.put(state.pending, ref, updated)}
  end

  defp store_event(state, _ref, _entry, _event), do: state

  defp cancel_check(state, ref, entry, reason) do
    report = emit_cancelled_from_entry(state, entry, reason)
    state = remove(state, ref, entry)

    # An already submitted HTTP request may still deliver metering. Close
    # admission now and let only this request finish under the transport bound.
    if Enum.any?(report.attempts, &(&1.outcome == :cancelled)) do
      timer = Process.send_after(self(), {:stop_late, ref}, state.timeout_ms)

      context =
        Map.take(report, [
          :evaluation_id,
          :event,
          :participant_id,
          :activation_id,
          :tenant_id,
          :call_id,
          :room_id,
          :incarnation_id,
          :source_turn_id,
          :response_turn_id,
          :transfer_invocation_id,
          :selected_provider,
          :actual_provider,
          :actual_model,
          :actual_request_id
        ])

      # Cancellation revoked the original Task reply alias. Monitor the transport
      # independently so a completed drain retires immediately.
      drain = %{
        pid: entry.pid,
        monitor: Process.monitor(entry.pid),
        timer: timer,
        context: context,
        attempts: report.attempts
      }

      %{state | late_reports: Map.put(state.late_reports, ref, drain)}
    else
      Process.exit(entry.pid, :kill)
      state
    end
  end

  defp record_late_event(
         state,
         evaluation_id,
         %{phase: :finished, ordinal: wire_ordinal, usage: usage} = event
       )
       when is_map(usage) and wire_ordinal in 1..2 do
    with {ref, drain} <-
           Enum.find(state.late_reports, fn {_ref, d} ->
             d.context.evaluation_id == evaluation_id
           end),
         attempt when not is_nil(attempt) <-
           Enum.find(
             drain.attempts,
             &(&1.ordinal == wire_ordinal - 1 and &1.outcome == :cancelled)
           ) do
      completed = %{
        attempt
        | model: event_model(event),
          request_id: event_request_id(event),
          outcome: event_outcome(event)
      }

      observations = Emission.late_observations(drain.context, completed, usage)
      if observations != [], do: dispatch_late_usage(state, observations)
      remaining = List.delete(drain.attempts, attempt)
      %{state | late_reports: Map.put(state.late_reports, ref, %{drain | attempts: remaining})}
    else
      _ -> state
    end
  end

  defp record_late_event(state, _evaluation_id, _event), do: state

  defp forget_late(state, ref) do
    case Map.pop(state.late_reports, ref) do
      {nil, _} ->
        state

      {drain, remaining} ->
        Process.cancel_timer(drain.timer)
        Process.demonitor(drain.monitor, [:flush])
        %{state | late_reports: remaining}
    end
  end

  defp dispatch_late_usage(%{on_late_usage: nil}, _observations), do: :ok

  defp dispatch_late_usage(%{on_late_usage: emit}, observations)
       when is_function(emit, 1) do
    try do
      emit.(observations)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
  end

  # --- actual physical attempts only ---

  defp actual_attempts(state, entry, started_wall, ended_wall) do
    entry.attempt_events
    |> Enum.uniq_by(&attempt_ordinal/1)
    |> Enum.sort_by(&attempt_ordinal/1)
    |> Enum.map(fn event ->
      ordinal = attempt_ordinal(event) - 1
      attempt_id = Map.fetch!(entry.attempt_ids, ordinal + 1)
      incomplete? = event.phase == :started

      %{
        attempt_id: attempt_id,
        ordinal: ordinal,
        provider: selected_or_event_provider(state, event),
        model: event_model(event),
        request_id: event_request_id(event),
        outcome: if(incomplete?, do: :cancelled, else: event_outcome(event)),
        error_code: event_error_code(event),
        started_at: attempt_time(entry, event[:started_at_ms], started_wall),
        ended_at: attempt_time(entry, event[:ended_at_ms], ended_wall),
        duration_ms:
          Map.get(event, :duration_ms, max(now() - Map.get(event, :started_at_ms, now()), 0)),
        retry_of: nil,
        usage: event_usage(event)
      }
    end)
    |> link_retries()
  end

  defp finished_attempt_event?(%{phase: :finished}), do: true
  defp finished_attempt_event?(%{"phase" => "finished"}), do: true
  # Legacy test shape with explicit attempt_id counts as actual.
  defp finished_attempt_event?(%{attempt_id: id}) when is_binary(id), do: true
  defp finished_attempt_event?(_), do: false

  defp attempt_ordinal(%{ordinal: ordinal}) when is_integer(ordinal), do: ordinal
  defp attempt_ordinal(%{"ordinal" => ordinal}) when is_integer(ordinal), do: ordinal
  defp attempt_ordinal(_), do: 0

  defp selected_or_event_provider(state, event) do
    case Map.get(event, :provider) || Map.get(event, "provider") do
      provider when is_binary(provider) -> provider
      _ -> state.selected_provider
    end
  end

  defp event_model(%{model: model}) when is_binary(model), do: model
  defp event_model(%{"model" => model}) when is_binary(model), do: model
  defp event_model(_), do: nil

  defp event_request_id(%{request_id: id}) when is_binary(id), do: id
  defp event_request_id(%{"request_id" => id}) when is_binary(id), do: id
  defp event_request_id(_), do: nil

  defp event_outcome(%{outcome: outcome}) when outcome in [:succeeded, :failed, :cancelled],
    do: outcome

  defp event_outcome(%{"outcome" => outcome})
       when outcome in ["succeeded", "failed", "cancelled"] do
    String.to_existing_atom(outcome)
  end

  defp event_outcome(_), do: :succeeded

  defp event_error_code(%{error_code: code}) when is_atom(code), do: code
  defp event_error_code(_), do: nil

  defp attempt_time(entry, milliseconds, _fallback) when is_integer(milliseconds) do
    DateTime.add(entry.started_wall, milliseconds - entry.started_mono, :millisecond)
  end

  defp attempt_time(_entry, _milliseconds, fallback), do: fallback

  defp event_usage(%{usage: usage}) when is_map(usage), do: usage
  defp event_usage(_), do: :unknown

  defp link_retries([]), do: []

  defp link_retries([first | rest]) do
    {linked, _} =
      Enum.map_reduce([first | rest], nil, fn attempt, previous_id ->
        attempt =
          if previous_id == nil do
            %{attempt | retry_of: nil}
          else
            %{attempt | retry_of: attempt.retry_of || previous_id}
          end

        {attempt, attempt.attempt_id}
      end)

    linked
  end

  defp actual_provider(%{provider: provider}) when is_binary(provider), do: provider
  defp actual_provider(_), do: nil

  defp actual_model(%{model: model}) when is_binary(model), do: model
  defp actual_model(_), do: nil

  defp actual_request_id(%{request_id: id}) when is_binary(id), do: id
  defp actual_request_id(_), do: nil

  defp normalize_outcomes(questions, outcomes) when is_list(outcomes) do
    by_id =
      Map.new(outcomes, fn outcome ->
        id =
          Map.get(outcome, :question_id) ||
            (is_map(Map.get(outcome, :question)) && Map.get(outcome.question, :id))

        {id, outcome}
      end)

    Enum.map(questions, fn question ->
      case Map.fetch(by_id, question.id) do
        {:ok, detail} ->
          outcome = Map.get(detail, :outcome)

          if outcome in [:passed, :failed, :unavailable] do
            %{
              question_id: question.id,
              probability_yes: Map.get(detail, :probability_yes),
              inferred_answer: Map.get(detail, :inferred_answer),
              outcome: outcome
            }
          else
            %{
              question_id: question.id,
              probability_yes: nil,
              inferred_answer: nil,
              outcome: :unavailable
            }
          end

        _ ->
          %{
            question_id: question.id,
            probability_yes: nil,
            inferred_answer: nil,
            outcome: :unavailable
          }
      end
    end)
  end

  defp extract_correlation(evidence, event, proposal) when is_map(evidence) do
    nested =
      Map.get(evidence, "correlation") || Map.get(evidence, :correlation) ||
        %{}

    nested = if is_map(nested), do: nested, else: %{}

    get = fn key ->
      Map.get(nested, key) || Map.get(nested, to_string(key)) || Map.get(evidence, key) ||
        Map.get(evidence, to_string(key))
    end

    source_participant_id = get.(:source_participant_id)
    source_turn_id = get.(:source_turn_id)
    response_turn_id = get.(:response_turn_id)
    transfer_invocation_id = get.(:transfer_invocation_id)
    command_id = get.(:command_id)
    candidate_attempt_id = get.(:candidate_attempt_id) || get.(:attempt_id)

    {source_turn_id, response_turn_id, transfer_invocation_id} =
      case event do
        :before_turn when is_nil(source_turn_id) and is_binary(proposal) ->
          {proposal, response_turn_id, transfer_invocation_id}

        :after_turn when is_nil(response_turn_id) and is_binary(proposal) ->
          {source_turn_id, proposal, transfer_invocation_id}

        :before_outgoing_transfer when is_nil(transfer_invocation_id) and is_binary(proposal) ->
          {source_turn_id, response_turn_id, proposal}

        _ ->
          {source_turn_id, response_turn_id, transfer_invocation_id}
      end

    %{
      source_participant_id: source_participant_id,
      source_policy_revision: get.(:source_policy_revision),
      source_turn_id: source_turn_id,
      response_turn_id: response_turn_id,
      transfer_invocation_id: transfer_invocation_id,
      command_id: command_id,
      candidate_attempt_id: candidate_attempt_id
    }
  end

  # Input admission pins the text or STT interval before queueing. Other events
  # originate in this activation, so capture their interval when the check starts.
  defp pin_source_interval(correlation, event, %{incarnation_id: incarnation} = state)
       when event in [:after_turn, :before_outgoing_transfer] and is_binary(incarnation) do
    source = correlation.source_participant_id || state.participant_id

    with true <- is_binary(source),
         router when is_pid(router) <- TranscriptRouter.whereis(incarnation),
         {:ok, %{source_policy: %{"media_policy_revision" => revision}}} <-
           TranscriptRouter.project_current(router, source, MapSet.new()) do
      %{correlation | source_policy_revision: revision}
    else
      _ -> %{correlation | source_policy_revision: nil}
    end
  end

  defp pin_source_interval(correlation, _event, _state), do: correlation

  defp permitted_for_check?(state, :before_turn, correlation),
    do: input_route?(state, correlation.source_participant_id, correlation.source_policy_revision)

  defp permitted_for_check?(_state, _event, _correlation), do: true

  defp input_route?(%{enforce_input_route?: false}, _source, _revision), do: true

  defp input_route?(state, source, revision) when is_binary(source) and is_integer(revision) do
    projection = %Projection{
      tenant_id: state.tenant_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      source_participant_id: source,
      policy_revision: revision,
      recipient_participant_ids: MapSet.new([state.participant_id])
    }

    TranscriptRouter.permitted?(projection, state.participant_id)
  end

  defp input_route?(_state, _source, _revision), do: false

  defp remove(state, ref, _entry) do
    entry = Map.get(state.pending, ref)

    if entry do
      Process.cancel_timer(entry.timer)
      Process.demonitor(entry.owner_ref, [:flush])
      Process.demonitor(ref, [:flush])
    end

    %{state | pending: Map.delete(state.pending, ref)}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
