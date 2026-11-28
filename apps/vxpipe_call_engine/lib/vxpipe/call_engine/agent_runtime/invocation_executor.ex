defmodule Vxpipe.CallEngine.AgentRuntime.InvocationExecutor do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.Executor

  alias Vxpipe.CallEngine.AgentRuntime.Correlation
  alias Vxpipe.CallEngine.RoomAuthority
  alias Vxpipe.CallEngine.Tool.{Hangup, InvocationBinding, InvocationRegistry}

  alias Vxpipe.CallEngine.Tool.TerminalCompletionBarrier

  @impl true
  def submit(
        %InvocationBinding{} = binding,
        arguments,
        %Correlation{} = correlation,
        invocation_id
      ) do
    result =
      InvocationRegistry.submit(
        correlation.invocation_registry,
        binding,
        arguments,
        correlation.tool_context,
        invocation_id
      )

    if match?({:accepted, _}, result) and
         InvocationBinding.announced_action?(binding, arguments),
       do: {:accepted, :await_completion},
       else: result
  end

  def submit(_binding, _arguments, _correlation, _invocation_id), do: {:error, :rejected}

  @impl true
  def preflight(
        %InvocationBinding{} = binding,
        _arguments,
        %Correlation{} = correlation,
        _invocation_id
      ) do
    terminal_preflight(binding, correlation)
  end

  def preflight(_binding, _arguments, _correlation, _invocation_id), do: :ok

  @doc """
  Host completion barrier: ordinary results FINISH before terminal effect.

  Called by `RequestRunner` after ordinary submits, before terminal submits.
  Only observes the registry; never calls Room, never leases/consumes, so
  original correlation and nonblocking caller-turn admission are preserved.
  Awaits under an absolute bound derived from ordinary deadlines; stale
  activation cancels. On `{:error, :ordinary_failed}` the caller withholds the
  terminal effect and returns a correlated result for a later distinct proposal.
  """
  @spec await_ordinary_completions(Correlation.t(), [String.t()]) ::
          :ok | {:error, :ordinary_failed | :timeout | :stale}
  @impl true
  def await_ordinary_completions(%Correlation{} = correlation, ordinary_ids)
      when is_list(ordinary_ids) do
    TerminalCompletionBarrier.await_ordinary(
      correlation.invocation_registry,
      ordinary_ids,
      timeout_ms: barrier_timeout_ms(correlation, ordinary_ids)
    )
  end

  def await_ordinary_completions(_correlation, _ordinary_ids), do: :ok

  # Bounded cancellable admission runs before `RequestRunner.begin_submission/0`.
  # A synchronous room query after `begin_submission/0` would deadlock:
  # worker -> Room -> Coordinator.interrupt -> Session.cancel (waits for commit).
  # The check matches actual invocation bindings (aliases), not tool names, and
  # ignores arguments: announced and silent hangups and all participant
  # transfers are gated alike. Effect-time revalidation in `EndCall` and the
  # transfer `Authorizer` still guards races where the floor rises after
  # preflight.
  defp terminal_preflight(
         %InvocationBinding{handler: {:platform, Hangup}},
         %Correlation{} = correlation
       ),
       do: terminal_room_preflight(correlation)

  defp terminal_preflight(
         %InvocationBinding{handler: {:participant_transfer, _}},
         %Correlation{} = correlation
       ),
       do: terminal_room_preflight(correlation)

  defp terminal_preflight(%InvocationBinding{}, %Correlation{}), do: :ok

  defp terminal_room_preflight(%Correlation{} = correlation) do
    case RoomAuthority.terminal_submission_admission(correlation.tool_context) do
      :ok -> :ok
      {:error, :caller_answer_pending} -> {:error, :caller_answer_pending}
      {:error, :unavailable} -> {:error, :unavailable}
    end
  end

  # Absolute bound: furthest ordinary deadline plus a buffer, capped. Stale
  # registry (running_execution unavailable for all) falls back to a short
  # bound so the barrier cancels instead of waiting indefinitely.
  defp barrier_timeout_ms(%Correlation{} = correlation, ordinary_ids) do
    now_ms = System.monotonic_time(:millisecond)

    deadlines =
      for invocation_id <- ordinary_ids,
          {:ok, execution} <-
            [safe_running_execution(correlation.invocation_registry, invocation_id)],
          is_integer(execution.deadline_ms),
          do: execution.deadline_ms

    case deadlines do
      [] ->
        1_000

      _ ->
        remaining = Enum.max(deadlines) - now_ms
        min(max(remaining + 1_000, 1_000), 30_000)
    end
  end

  defp safe_running_execution(registry, invocation_id) do
    InvocationRegistry.running_execution(registry, invocation_id)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
