defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.IdlePause do
  @moduledoc "Schedules genuine tool observations and a single continuation during an idle hold."

  alias Vxpipe.AgentRuntime.Session
  alias Vxpipe.CallEngine.AgentRuntime.CompletionContinuation
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.State

  def arm(%State{} = state, token, context) do
    origin = state.current || state.awaiting_output

    if origin != nil and %{context | tool_call_id: nil} == origin.correlation.tool_context do
      pause = %{
        token: token,
        invocation_id: context.tool_call_id,
        timeout: nil,
        cancelled?: false,
        completed?: false
      }

      %{
        state
        | idle_pause: pause,
          idle_invocations: MapSet.put(state.idle_invocations, context.tool_call_id)
      }
    else
      state
    end
  end

  def expire(%State{idle_pause: %{token: token} = pause} = state, token, command),
    do: %{state | idle_pause: %{pause | timeout: command}}

  def expire(state, _token, _command), do: state

  def cancel(%State{idle_pause: %{token: token, completed?: true}} = state, token),
    do: %{state | idle_pause: nil}

  def cancel(%State{idle_pause: %{token: token} = pause} = state, token),
    do: %{state | idle_pause: %{pause | cancelled?: true, timeout: nil}}

  def cancel(state, _token), do: state

  def retain?(state, continuation),
    do:
      state.idle_pause != nil or
        MapSet.member?(state.idle_invocations, continuation.invocation_id)

  def retain(state, continuation) do
    correlation = %{
      activation_id: state.activation_id,
      tool_completion_id: continuation.invocation_id
    }

    with :ok <- Session.record_engine(state.session, continuation.command.content, correlation),
         :ok <- CompletionContinuation.acknowledge(state.invocation_registry, continuation) do
      pause = completed(state.idle_pause, continuation.invocation_id)

      {:ok,
       %{
         state
         | idle_pause: pause,
           idle_invocations: MapSet.delete(state.idle_invocations, continuation.invocation_id)
       }}
    else
      _unavailable ->
        _ = CompletionContinuation.release(state.invocation_registry, continuation)
        {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def take_timeout(%State{idle_pause: %{timeout: command, completed?: true}} = state)
      when not is_nil(command),
      do: {:ready, command, %{state | idle_pause: nil}}

  def take_timeout(%State{idle_pause: nil} = state), do: {:open, state}
  def take_timeout(state), do: {:waiting, state}

  defp completed(%{invocation_id: id, cancelled?: true}, id), do: nil
  defp completed(%{invocation_id: id} = pause, id), do: %{pause | completed?: true}
  defp completed(pause, _id), do: pause
end
