defmodule Vxpipe.CallEngine.AgentRuntime.InvocationExecutor do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.Executor

  alias Vxpipe.CallEngine.AgentRuntime.Correlation
  alias Vxpipe.CallEngine.RoomAuthority
  alias Vxpipe.CallEngine.Tool.{Hangup, InvocationBinding, InvocationRegistry}

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
end
