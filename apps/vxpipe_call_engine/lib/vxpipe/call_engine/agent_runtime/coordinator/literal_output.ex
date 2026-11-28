defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.LiteralOutput do
  @moduledoc "Admits participant-owned fixed speech before playback or conversation history."

  alias Vxpipe.AgentRuntime.Session

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{
    ActiveRequest,
    History,
    OutputSettlement,
    State
  }

  alias Vxpipe.CallEngine.Guardrails.{Deadline, Evidence, Participant}

  def start(state, command, text, kind) do
    correlation = ActiveRequest.correlation(command, State.request_options(state))
    literal = %{command: command, correlation: correlation, text: text, kind: kind, task: nil}

    cond do
      is_nil(state.guardrails) ->
        deliver(state, literal)

      kind == :hold and not is_nil(state.current) ->
        delay = max(correlation.deadline_ms - System.monotonic_time(:millisecond), 0)
        timer = :erlang.start_timer(delay, self(), :deferred_hold_deadline)
        {:ok, %{state | pending_literal: Map.put(literal, :timer, timer)}}

      true ->
        {:ok, start_check(state, literal)}
    end
  end

  def resume_hold(%{pending_literal: %{timer: timer} = literal} = state) do
    Process.cancel_timer(timer)

    if Deadline.open?(literal.correlation.deadline_ms),
      do: start_check(state, Map.delete(literal, :timer)),
      else: finish(state, {:error, :timeout})
  end

  defp start_check(state, literal) do
    server = state.guardrails
    agent = state.agent_participant_id
    session = state.session
    deadline = Deadline.evaluation(literal.correlation.deadline_ms)

    task =
      Task.Supervisor.async_nolink(state.request_supervisor, fn ->
        evidence = %{
          "text" => literal.text,
          "correlation" => %{
            "command_id" => literal.command.id,
            "source_participant_id" => agent,
            "source_policy_revision" => literal.correlation.tool_context.agent_policy_revision,
            "response_turn_id" => literal.command.correlation_id
          },
          "recent_context" => Evidence.recent(Session.recent_dialogue(session), agent)
        }

        Participant.check(server, :after_turn, literal.command.correlation_id, evidence, deadline)
      end)

    %{state | pending_literal: %{literal | task: task}}
  end

  def finish(state, verdict) do
    literal = state.pending_literal
    state = %{state | pending_literal: nil}

    case verdict do
      :passed ->
        revision = literal.correlation.tool_context.agent_policy_revision

        if Participant.input_permitted?(state.guardrails, state.agent_participant_id, revision) and
             Deadline.open?(literal.correlation.deadline_ms) do
          case deliver(state, literal) do
            {:ok, state} -> state
            {:error, _} -> fail(state, literal, :guardrail_unavailable)
          end
        else
          fail(state, literal, :guardrail_unavailable)
        end

      {:blocked, _} ->
        fail(state, literal, :guardrail_blocked)

      _ ->
        fail(state, literal, :guardrail_unavailable)
    end
  end

  def cancel(%{pending_literal: nil} = state), do: state

  def cancel(state) do
    literal = state.pending_literal

    case literal do
      %{timer: timer} -> Process.cancel_timer(timer)
      %{task: task} -> Task.shutdown(task, :brutal_kill)
    end

    fail(%{state | pending_literal: nil}, literal, :interrupted)
  end

  defp deliver(state, %{kind: :greeting} = literal) do
    with :ok <- Session.record_assistant(state.session, literal.text, literal.correlation) do
      publish(state, literal)
      history = History.record(state.history, literal.command, literal.correlation)

      awaiting =
        if state.history_mode == :host_settled,
          do: OutputSettlement.pending(literal.command, literal.correlation, literal.text)

      {:ok, %{state | history: history, awaiting_output: awaiting}}
    end
  end

  defp deliver(state, %{kind: :hold} = literal) do
    publish(state, literal)
    {:ok, state}
  end

  defp publish(state, literal) do
    send(state.owner, {:vxpipe_capability_text, self(), literal.command, literal.text})
    send(state.owner, {:vxpipe_capability_text_complete, self(), literal.command})
  end

  defp fail(state, literal, reason) do
    send(state.owner, {:vxpipe_capability_failed, self(), literal.command, reason})
    state
  end
end
