defmodule Vxpipe.CallEngine.Guardrails.TransferAdmission do
  @moduledoc false

  # Joint After-turn / Before-outgoing-transfer admission for model rounds that
  # propose caller-facing speech and/or a transfer, plus the single-transfer
  # gate used at tool-execution time (native speech and the unadmitted
  # fallback). Operates on the runtime's typed %RoundCandidate{} with dot
  # access; validation precedes all guardrail I/O.
  #
  # Joint checks on one participant share a single stable proposal
  # (correlation_id:attempt) so the Participant busy fence treats the pair as
  # concurrent rather than conflicting. Transfer call IDs travel separately as
  # invocation IDs in evidence and binds. Transfer detection uses the
  # binding-derived terminal_kinds map from wiring, never tool-name matching;
  # unknown tool kinds fail closed.
  #
  # Privacy: repair lines forwarded here come only from the Guardrails service
  # (authored responses or generated fallbacks). Only descriptor names and
  # binding-derived kinds identify proposed tools in shared checker evidence.
  # Stale verdicts (elapsed response deadline, cancelled/stale checker
  # results) fence to failures and never release effects.

  alias Vxpipe.AgentRuntime.{RoundCandidate, ToolCall, ToolRegistry}
  alias Vxpipe.CallEngine.Tool.InvocationBinding
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request, as: TransferRequest
  alias Vxpipe.CallEngine.Guardrails.{CheckClient, Deadline, Evidence}

  @stable_event_order [:after_turn, :before_outgoing_transfer]
  @max_current_evidence_bytes 8 * 1_024

  @type check_fun ::
          (term(), :after_turn | :before_outgoing_transfer, String.t(), map(), integer() ->
             :passed | {:blocked, [String.t()]} | {:error, atom()})

  @type host :: %{
          required(:guardrails) => GenServer.server() | nil,
          required(:activation_id) => String.t(),
          required(:incarnation_id) => String.t(),
          required(:after_questions) => [map()],
          required(:transfer_questions) => [map()],
          required(:policy_revision) => non_neg_integer(),
          required(:terminal_kinds) => %{optional(String.t()) => :transfer | :hangup | :ordinary},
          optional(:check) => check_fun() | nil,
          optional(:evaluation_timeout_ms) => pos_integer(),
          optional(:response_deadline_ms) => integer() | :infinity,
          optional(:maximum_feedback_bytes) => pos_integer()
        }

  @type verdict_bind :: %{
          invocation_id: String.t(),
          verdict: :passed,
          source_activation_id: String.t(),
          source_participant_id: String.t() | nil,
          destination_call_spec_key: String.t() | nil,
          policy_digest: binary(),
          policy_revision: non_neg_integer(),
          incarnation_id: String.t(),
          checked_at_ms: integer(),
          source: :bound
        }

  @spec joint_admit(RoundCandidate.t(), map(), host()) ::
          {:accept, %{binds: [verdict_bind()]}}
          | {:repair,
             %{messages: [String.t()], failures: [%{event: atom(), messages: [String.t()]}]}}
          | {:failure, :error | :cancelled | :stale | :oversized}
  def joint_admit(%RoundCandidate{} = candidate, context, %{} = host) do
    deadline =
      Deadline.intersect(
        host[:response_deadline_ms],
        Map.get(context[:correlation] || %{}, :deadline_ms)
      )

    host = Map.put(host, :response_deadline_ms, deadline)

    with :ok <- response_admitted?(host),
         :ok <- validate_candidate(candidate, context),
         {:ok, proposal} <- stable_proposal(candidate, context),
         {:ok, checks} <- planned_checks(candidate, host, proposal),
         {:ok, results} <- run_checks(checks, candidate, host, proposal, context),
         :ok <- response_admitted?(host) do
      combine(results, candidate, host)
    else
      {:failure, _reason} = failure -> failure
      _invalid -> {:failure, :error}
    end
  rescue
    _error -> {:failure, :error}
  catch
    _kind, _reason -> {:failure, :error}
  end

  def joint_admit(_candidate, _context, _host), do: {:failure, :error}

  @spec check_transfer(map()) :: CheckClient.verdict()
  def check_transfer(%{} = attrs) do
    with {:ok, server, check} <- resolve_transfer_checker(attrs),
         :ok <- transfer_evidence_budget(attrs) do
      run_check(
        check,
        server,
        :before_outgoing_transfer,
        invocation_id(attrs),
        transfer_evidence(attrs),
        transfer_deadline(attrs)
      )
    end
  end

  @spec policy_digest([map()]) :: binary() | nil
  def policy_digest([]), do: nil

  def policy_digest(questions) when is_list(questions) do
    canonical =
      questions
      |> Enum.map(&digest_fields/1)
      |> Enum.sort()

    :crypto.hash(:sha256, :erlang.term_to_binary({:guardrails_v1, canonical}))
  end

  defp digest_fields(%{id: id} = question) do
    {
      id,
      Map.get(question, :question),
      Map.get(question, :required_answer),
      Map.get(question, :threshold_hundredths),
      Map.get(question, :response)
    }
  end

  defp digest_fields(%{"id" => id} = question) do
    {
      id,
      Map.get(question, "question"),
      Map.get(question, "required_answer"),
      Map.get(question, "probability_threshold"),
      Map.get(question, "response")
    }
  end

  # --- validation before guard checks ---

  defp validate_candidate(%RoundCandidate{} = candidate, context) do
    with true <- is_binary(candidate.text),
         true <- is_list(candidate.tool_calls),
         true <- Enum.all?(candidate.tool_calls, &ToolCall.valid?/1),
         true <- is_boolean(candidate.speech?),
         true <- is_boolean(candidate.tool_only?),
         true <- is_integer(candidate.attempt) and candidate.attempt > 0,
         true <- is_integer(candidate.maximum_bytes) and candidate.maximum_bytes > 0,
         true <- is_map(candidate.correlation),
         true <- is_map(context),
         true <- is_map(context[:correlation]) do
      :ok
    else
      _invalid -> {:failure, :error}
    end
  end

  defp stable_proposal(%RoundCandidate{attempt: attempt}, %{correlation: correlation}) do
    case correlation_id(correlation) do
      nil -> {:failure, :error}
      base when is_binary(base) and base != "" -> {:ok, base <> ":" <> Integer.to_string(attempt)}
      _invalid -> {:failure, :error}
    end
  end

  defp stable_proposal(_candidate, _context), do: {:failure, :error}

  defp correlation_id(%{correlation_id: base}) when is_binary(base) and base != "", do: base
  defp correlation_id(%{request_id: base}) when is_binary(base) and base != "", do: base
  defp correlation_id(_correlation), do: nil

  # --- planning (binding-derived kinds, no hardcoded names) ---

  defp planned_checks(%RoundCandidate{} = candidate, host, proposal) do
    after_questions = host[:after_questions] || []
    transfer_questions = host[:transfer_questions] || []
    kinds = host[:terminal_kinds]

    with :ok <- validate_questions(after_questions),
         :ok <- validate_questions(transfer_questions),
         :ok <- validate_kinds(candidate, kinds) do
      checks = maybe_after_turn([], candidate, after_questions, proposal)
      plan_transfer(checks, candidate, transfer_questions, kinds, proposal)
    end
  end

  defp validate_questions(questions) when is_list(questions), do: :ok
  defp validate_questions(_questions), do: {:failure, :error}

  defp validate_kinds(%RoundCandidate{tool_calls: calls}, kinds) when is_map(kinds) do
    if Enum.all?(calls, &Map.has_key?(kinds, &1.name)) do
      :ok
    else
      {:failure, :error}
    end
  end

  defp validate_kinds(_candidate, _kinds), do: {:failure, :error}

  defp maybe_after_turn(
         checks,
         %RoundCandidate{speech?: true, tool_only?: false},
         questions,
         proposal
       )
       when questions != [] do
    [{:after_turn, proposal} | checks]
  end

  defp maybe_after_turn(checks, _candidate, _questions, _proposal), do: checks

  defp plan_transfer(checks, _candidate, [], _kinds, _proposal), do: {:ok, checks}

  defp plan_transfer(checks, %RoundCandidate{tool_calls: calls}, _questions, kinds, proposal) do
    case Enum.filter(calls, &(Map.fetch!(kinds, &1.name) == :transfer)) do
      [] -> {:ok, checks}
      [call] -> {:ok, [{:before_outgoing_transfer, proposal, call} | checks]}
      _multiple -> {:failure, :error}
    end
  end

  # --- running checks against the participant service ---

  defp run_checks([], _candidate, _host, _proposal, _context), do: {:ok, []}

  defp run_checks(checks, candidate, host, proposal, context) do
    guardrails = host[:guardrails]
    deadline_ms = joint_deadline(host)

    cond do
      is_nil(guardrails) ->
        {:failure, :error}

      true ->
        with :ok <- response_admitted?(host),
             :ok <- candidate_evidence_budget(candidate),
             true <- valid_tool_arguments?(candidate.tool_calls, context) do
          proposed_calls =
            Enum.map(candidate.tool_calls, fn call ->
              %{
                "id" => call.id,
                "name" => call.name,
                "kind" => Atom.to_string(Map.fetch!(host.terminal_kinds, call.name))
              }
            end)

          current = %{
            "text" => candidate.text,
            "correlation" => turn_correlation(context.correlation, candidate.speech?, host),
            "recent_context" =>
              Evidence.recent(Map.get(context, :recent_dialogue), host[:agent_participant_id]),
            "triggering_input" =>
              Evidence.triggering_input(context.correlation, Map.get(context, :triggering_input)),
            "attempt_id" => proposal,
            "proposed_calls" => proposed_calls
          }

          tasks =
            Enum.map(checks, fn
              {:after_turn, check_proposal} ->
                evidence = Map.put(current, "event", "after_turn")

                issue_check(
                  host,
                  guardrails,
                  :after_turn,
                  check_proposal,
                  evidence,
                  deadline_ms,
                  nil
                )

              {:before_outgoing_transfer, check_proposal, %ToolCall{} = call} ->
                evidence =
                  Map.merge(current, %{
                    "event" => "before_outgoing_transfer",
                    "destination" => transfer_destination(call),
                    "reason" => transfer_reason(call),
                    "invocation_id" => call.id
                  })

                issue_check(
                  host,
                  guardrails,
                  :before_outgoing_transfer,
                  check_proposal,
                  evidence,
                  deadline_ms,
                  call
                )
            end)

          await_checks(tasks, deadline_ms)
        end
    end
  end

  defp valid_tool_arguments?([], _context), do: true

  defp valid_tool_arguments?(calls, %{tool_registry: %ToolRegistry{} = registry}) do
    Enum.all?(calls, fn call ->
      case ToolRegistry.resolve(registry, call.name, call.arguments, :admission) do
        {:ok, %{binding: %InvocationBinding{handler: {:participant_transfer, binding}}}} ->
          match?({:ok, _, _, _}, TransferRequest.resolve_arguments(binding, call.arguments))

        {:ok, _ordinary} ->
          true

        {:error, _} ->
          false
      end
    end)
  end

  defp valid_tool_arguments?(_calls, _context), do: false

  defp issue_check(host, guardrails, event, proposal, evidence, deadline_ms, call) do
    check = check_fun(host)

    Task.async(fn ->
      {event, call, run_check(check, guardrails, event, proposal, evidence, deadline_ms)}
    end)
  end

  defp turn_correlation(correlation, speech?, host) do
    turn = Map.get(correlation, :correlation_id)
    caller? = match?(%{tool_context: %{request_origin: :caller}}, correlation)

    %{
      "command_id" => Map.get(correlation, :command_id),
      "source_participant_id" => host[:agent_participant_id],
      "source_turn_id" => if(caller?, do: turn),
      "response_turn_id" => if(speech?, do: turn)
    }
  end

  defp response_admitted?(%{response_deadline_ms: :infinity}), do: :ok
  defp response_admitted?(%{response_deadline_ms: nil}), do: :ok

  defp response_admitted?(%{response_deadline_ms: deadline_ms}) when is_integer(deadline_ms) do
    if System.monotonic_time(:millisecond) < deadline_ms, do: :ok, else: {:failure, :error}
  end

  defp response_admitted?(_host), do: :ok

  defp joint_deadline(host) do
    timeout = host[:evaluation_timeout_ms] || Deadline.evaluation_timeout_ms()
    Deadline.evaluation(host[:response_deadline_ms], timeout)
  end

  defp await_checks(tasks, deadline_ms) do
    remaining = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    results =
      tasks
      |> Task.yield_many(remaining)
      |> Enum.map(fn {task, reply} ->
        case reply || Task.shutdown(task, :brutal_kill) do
          {:ok, result} -> result
          _ -> {nil, nil, {:error, :timeout}}
        end
      end)

    {:ok, results}
  end

  # --- combining (stable event order, per-event failures, binds) ---

  defp combine(results, candidate, host) do
    errors =
      Enum.filter(results, fn {_event, _proposal, outcome} -> match?({:error, _}, outcome) end)

    case errors do
      [{_event, _proposal, {:error, reason}} | _] ->
        {:failure, fence_reason(reason)}

      [] ->
        failures =
          @stable_event_order
          |> Enum.flat_map(fn event ->
            case lines_for(results, event) do
              [] -> []
              lines -> [%{event: event, messages: lines}]
            end
          end)

        case failures do
          [] -> {:accept, %{binds: accept_binds(results, candidate, host)}}
          _ -> repair_or_fail(failures, host, results)
        end
    end
  end

  defp lines_for(results, event) do
    Enum.flat_map(results, fn
      {^event, _, {:blocked, lines}} -> lines
      {^event, _, {:blocked, lines, _callback}} -> lines
      _ -> []
    end)
  end

  defp fence_reason(:cancelled), do: :cancelled
  defp fence_reason(:stale), do: :stale
  defp fence_reason(:oversized), do: :oversized
  defp fence_reason(_reason), do: :error

  defp repair_or_fail(failures, host, results) do
    lines = Enum.flat_map(failures, & &1.messages)

    cond do
      not feedback_valid?(lines) ->
        {:failure, :error}

      byte_size(Vxpipe.AgentRuntime.GuardrailFeedback.encode(failures)) >
          Map.get(host, :maximum_feedback_bytes, 256 * 1_024) ->
        {:failure, :oversized}

      true ->
        callbacks = for {_, _, {:blocked, _, callback}} <- results, do: callback
        repair = %{messages: lines, failures: failures}

        if callbacks == [],
          do: {:repair, repair},
          else: {:repair, Map.put(repair, :on_dispatch, fn -> Enum.each(callbacks, & &1.()) end)}
    end
  end

  defp accept_binds(results, candidate, host) do
    for {:before_outgoing_transfer, %ToolCall{} = call, :passed} <- results do
      %{
        invocation_id: call.id,
        command_id: Map.get(candidate.correlation, :command_id),
        expires_at_ms: host[:response_deadline_ms],
        verdict: :passed,
        source_activation_id: host[:activation_id],
        source_participant_id: host[:agent_participant_id],
        destination_call_spec_key: transfer_destination(call),
        policy_digest: policy_digest(host[:transfer_questions]),
        policy_revision: host[:policy_revision],
        incarnation_id: host[:incarnation_id],
        checked_at_ms: System.monotonic_time(:millisecond),
        source: :bound
      }
    end
  end

  # --- single transfer gate ---

  defp resolve_transfer_checker(%{policy_digest: nil}), do: :passed

  defp resolve_transfer_checker(%{policy_digest: _digest, guardrails: nil}),
    do: {:error, :unavailable}

  defp resolve_transfer_checker(%{guardrails: server} = attrs) when not is_nil(server) do
    case Map.get(attrs, :check) do
      check when is_function(check, 5) -> {:ok, server, check}
      nil -> {:ok, server, &CheckClient.check_with_receipt/5}
      _invalid -> {:error, :invalid_result}
    end
  end

  defp resolve_transfer_checker(_attrs), do: {:error, :unavailable}

  defp run_check(check, server, event, proposal, evidence, deadline_ms) do
    try do
      with true <- Deadline.open?(deadline_ms),
           verdict = check.(server, event, proposal, evidence, deadline_ms),
           true <- Deadline.open?(deadline_ms) do
        validate_check_result(verdict)
      else
        false -> {:error, :timeout}
      end
    rescue
      _exception -> {:error, :unavailable}
    catch
      :exit, _reason -> {:error, :cancelled}
      _kind, _reason -> {:error, :unavailable}
    end
  end

  defp validate_check_result(:passed), do: :passed

  defp validate_check_result({:blocked, lines}) do
    if feedback_valid?(lines), do: {:blocked, lines}, else: {:error, :invalid_result}
  end

  defp validate_check_result({:blocked, lines, callback}) when is_function(callback, 0) do
    if feedback_valid?(lines), do: {:blocked, lines, callback}, else: {:error, :invalid_result}
  end

  defp validate_check_result({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp validate_check_result(_invalid), do: {:error, :invalid_result}

  defp check_fun(%{check: check}) when is_function(check, 5), do: check
  defp check_fun(_host), do: &CheckClient.check_with_receipt/5

  # --- evidence (permission-filtered, string keys only) ---

  defp transfer_evidence(%{} = attrs) do
    %{
      "event" => "before_outgoing_transfer",
      "correlation" => %{"command_id" => attrs[:command_id]},
      "destination" => attrs[:destination],
      "reason" => attrs[:reason],
      "text" => attrs[:text] || ""
    }
  end

  defp transfer_evidence_budget(attrs) do
    current_bytes =
      byte_size(attrs[:destination] || "") + byte_size(attrs[:reason] || "") +
        byte_size(attrs[:text] || "")

    if current_bytes <= @max_current_evidence_bytes, do: :ok, else: {:error, :oversized}
  end

  defp transfer_deadline(attrs) do
    Deadline.intersect(joint_deadline(attrs), attrs[:deadline_ms])
  end

  defp candidate_evidence_budget(candidate) do
    # Count the model's complete proposed calls locally, including JSON escaping.
    # A tool's input schema validates arguments; it grants no disclosure permission.
    calls_bytes =
      case candidate.tool_calls do
        [] ->
          0

        calls ->
          calls
          |> Enum.map(fn call -> %{id: call.id, name: call.name, arguments: call.arguments} end)
          |> JSON.encode_to_iodata!()
          |> IO.iodata_length()
      end

    if byte_size(candidate.text) + calls_bytes <= @max_current_evidence_bytes,
      do: :ok,
      else: {:failure, :oversized}
  end

  defp feedback_valid?(lines) when is_list(lines) and lines != [] do
    Enum.all?(lines, &(is_binary(&1) and &1 != ""))
  end

  defp feedback_valid?(_lines), do: false

  # Budget covers the exact private JSON envelope the runtime feeds back,
  # including per-event grouping overhead — not just the flat lines.
  # --- candidate helpers (dot access on typed structs) ---

  defp transfer_destination(%ToolCall{arguments: arguments}) when is_map(arguments) do
    case Map.get(arguments, "destination") do
      destination when is_binary(destination) -> destination
      _missing -> nil
    end
  end

  defp transfer_destination(_call), do: nil

  defp transfer_reason(%ToolCall{arguments: arguments}) when is_map(arguments) do
    case Map.get(arguments, "reason") do
      reason when is_binary(reason) -> reason
      _missing -> nil
    end
  end

  defp transfer_reason(_call), do: nil

  defp invocation_id(%{invocation_id: id}) when is_binary(id), do: id
  defp invocation_id(%{"invocation_id" => id}) when is_binary(id), do: id
  defp invocation_id(_attrs), do: nil
end
