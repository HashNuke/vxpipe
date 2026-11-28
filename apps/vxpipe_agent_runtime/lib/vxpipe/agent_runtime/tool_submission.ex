defmodule Vxpipe.AgentRuntime.ToolSubmission do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Executor, ToolRegistry}

  def submit(calls, request, config) do
    with :ok <- validate_call_count(calls, config.maximum_tool_calls_per_round),
         :ok <- validate_unique_call_ids(calls),
         {:ok, resolved_calls} <- resolve_calls(calls, config.tool_registry),
         {:ok, preflight_rejections} <- preflight_resolved_calls(resolved_calls, request, config),
         :ok <- config.begin_submission.() do
      submit_resolved_calls(resolved_calls, preflight_rejections, request, config)
    end
  end

  defp validate_call_count(calls, maximum) do
    if length(calls) <= maximum, do: :ok, else: {:error, :tool_call_limit}
  end

  defp validate_unique_call_ids(calls) do
    call_ids = Enum.map(calls, & &1.id)

    if length(call_ids) == MapSet.size(MapSet.new(call_ids)) do
      :ok
    else
      {:error, :duplicate_tool_call}
    end
  end

  defp resolve_calls(calls, registry) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, resolved} ->
      case ToolRegistry.resolve(registry, call.name, call.arguments) do
        {:ok, descriptor} -> {:cont, {:ok, [{call, descriptor} | resolved]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Terminal tools (transfer/hangup, marked via typed host `terminal?` binding)
  # submit last globally, preserving model order within each partition. Ordinary
  # submits complete first, so a blocked ordinary submit delays terminal start.
  # The host `Executor.submit/4` acknowledgement remains the effect-time gate:
  # a terminal denial there becomes a rejected tool result without terminal
  # effects, while already-accepted ordinary submissions stand. After ordinary
  # submits, the host completion barrier (`Executor.await_ordinary_completions/2`,
  # when exported) waits until ordinary invocation results FINISH before any
  # terminal start, including unguarded and tool-only batches. If an ordinary
  # failed (or the wait times out/goes stale), terminal effects are withheld and
  # each terminal call gets a correlated rejected result for a later distinct
  # proposal. No synchronous room query runs here after `begin_submission/0`.
  defp submit_resolved_calls(resolved_calls, preflight_rejections, request, config) do
    {ordinary_calls, terminal_calls} =
      Enum.split_with(resolved_calls, fn {_call, descriptor} -> not terminal_tool?(descriptor) end)

    {ordinary_submissions, disposition, accepted_ordinary_ids} =
      Enum.reduce(ordinary_calls, {[], :non_blocking, []}, fn {call, descriptor},
                                                              {submissions, disposition,
                                                               accepted_ids} ->
        case Map.get(preflight_rejections, call.id) do
          nil ->
            case Executor.submit(
                   config.executor,
                   descriptor.binding,
                   call.arguments,
                   request.correlation,
                   call.id
                 ) do
              {:accepted, mode} ->
                {[{call, running_result(call)} | submissions],
                 submission_disposition(disposition, mode), [call.id | accepted_ids]}

              {:error, reason} ->
                {[{call, rejected_result(reason)} | submissions], disposition, accepted_ids}
            end

          reason ->
            {[{call, rejected_result(reason)} | submissions], disposition, accepted_ids}
        end
      end)

    case terminal_calls do
      [] ->
        {:ok, Enum.reverse(ordinary_submissions), disposition}

      _ ->
        submit_terminal_calls(
          terminal_calls,
          ordinary_submissions,
          disposition,
          Enum.reverse(accepted_ordinary_ids),
          preflight_rejections,
          request,
          config
        )
    end
  end

  defp submit_terminal_calls(
         terminal_calls,
         ordinary_submissions,
         disposition,
         accepted_ordinary_ids,
         preflight_rejections,
         request,
         config
       ) do
    barrier =
      if length(accepted_ordinary_ids) == length(ordinary_submissions),
        do: await_ordinary_barrier(config, request, accepted_ordinary_ids),
        else: {:error, :ordinary_failed}

    case barrier do
      :ok ->
        {submissions, disposition} =
          Enum.reduce(terminal_calls, {ordinary_submissions, disposition}, fn {call, descriptor},
                                                                              {submissions,
                                                                               disposition} ->
            case Map.get(preflight_rejections, call.id) do
              nil ->
                submit_one(call, descriptor, request, config, submissions, disposition)

              reason ->
                {[{call, rejected_result(reason)} | submissions], disposition}
            end
          end)

        {:ok, Enum.reverse(submissions), disposition}

      {:error, reason} ->
        {submissions, _disposition} =
          Enum.reduce(terminal_calls, {ordinary_submissions, disposition}, fn {call, _descriptor},
                                                                              {submissions,
                                                                               disposition} ->
            case Map.get(preflight_rejections, call.id) do
              nil ->
                {[{call, rejected_result(reason)} | submissions], disposition}

              preflight_reason ->
                {[{call, rejected_result(preflight_reason)} | submissions], disposition}
            end
          end)

        {:ok, Enum.reverse(submissions), disposition}
    end
  end

  defp await_ordinary_barrier(_config, _request, []), do: :ok

  defp await_ordinary_barrier(config, request, accepted_ordinary_ids) do
    # Cancellation preserves ordinary submissions in the exchange below. Only
    # the completion wait is interruptible; actual submit and commit stay atomic.
    waiting =
      Task.async(fn ->
        Executor.await_ordinary_completions(
          config.executor,
          request.correlation,
          accepted_ordinary_ids
        )
      end)

    ref = waiting.ref

    receive do
      {^ref, outcome} ->
        Process.demonitor(ref, [:flush])
        with :ok <- outcome, do: config.begin_submission.()

      :agent_runtime_abort_barrier ->
        Task.shutdown(waiting, :brutal_kill)
        {:error, :stale}
    end
  end

  defp submit_one(call, descriptor, request, config, submissions, disposition) do
    case Executor.submit(
           config.executor,
           descriptor.binding,
           call.arguments,
           request.correlation,
           call.id
         ) do
      {:accepted, mode} ->
        {[{call, running_result(call)} | submissions], submission_disposition(disposition, mode)}

      {:error, reason} ->
        {[{call, rejected_result(reason)} | submissions], disposition}
    end
  end

  defp terminal_tool?(%{terminal?: true}), do: true
  defp terminal_tool?(_descriptor), do: false

  # Room admission must stay cancellable while caller interruption waits on the session.
  defp preflight_resolved_calls(resolved_calls, request, config) do
    rejections =
      Enum.reduce(resolved_calls, %{}, fn {call, descriptor}, acc ->
        case Executor.preflight(
               config.executor,
               descriptor.binding,
               call.arguments,
               request.correlation,
               call.id
             ) do
          :ok -> acc
          {:error, reason} -> Map.put(acc, call.id, reason)
        end
      end)

    {:ok, rejections}
  end

  defp submission_disposition(:await_completion, _mode), do: :await_completion
  defp submission_disposition(_previous, :await_completion), do: :await_completion
  defp submission_disposition(:blocking, _mode), do: :blocking
  defp submission_disposition(_previous, mode), do: mode

  defp running_result(call),
    do: %{"invocation_id" => call.id, "status" => "running"}

  defp rejected_result(reason),
    do: %{"reason" => Atom.to_string(reason), "status" => "rejected"}
end
