defmodule Vxpipe.Providers.Google.STSSubmission do
  @moduledoc "One ordered unsent command retained during a Gemini socket switchover."

  alias Vxpipe.Providers.Google.{STSCommands, STSInput}

  def submit(command, from, %{resuming?: true, pending_input: nil} = state) do
    monitor = Process.monitor(elem(from, 0))
    {:noreply, %{state | pending_input: %{command: command, from: from, monitor: monitor}}}
  end

  def submit(_command, _from, %{resuming?: true} = state),
    do: {:reply, {:error, :busy}, state}

  def submit({:context, context, operation}, _from, state) do
    with {:ok, command} <- STSInput.context_command(operation),
         {:ok, bound} <- STSInput.bind_context(state, context, operation) do
      case STSCommands.execute(command, bound) do
        {:reply, {:error, _reason} = error, next} ->
          {:reply, error, %{next | interaction_context: state.interaction_context}}

        result ->
          result
      end
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def submit({:command, command}, _from, state), do: STSCommands.execute(command, state)

  def release(%{pending_input: nil} = state), do: {:ok, state}

  def release(state) do
    pending = state.pending_input
    Process.demonitor(pending.monitor, [:flush])
    state = %{state | pending_input: nil}

    case submit(pending.command, pending.from, state) do
      {:reply, reply, state} ->
        GenServer.reply(pending.from, reply)
        {:ok, state}

      {:stop, _reason, reply, _state} ->
        GenServer.reply(pending.from, reply)
        {:error, :session_failed}
    end
  end
end
