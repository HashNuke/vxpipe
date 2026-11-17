defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.OutputSettlement do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Message, Session}
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.State

  @spec await(State.t()) :: State.t()
  def await(%State{history_mode: :host_settled, current: current} = state)
      when not is_nil(current) do
    %{state | awaiting_output: %{command: current.command, correlation: current.correlation}}
  end

  def await(%State{} = state), do: state

  @spec settle(State.t(), struct(), String.t() | nil) ::
          {:ok, State.t()} | :ignored | {:error, :unavailable}
  def settle(%State{awaiting_output: nil}, _command, _text), do: :ignored

  def settle(%State{} = state, command, text) do
    pending = state.awaiting_output

    if identity(pending.command) == identity(command) do
      with {:ok, message} <- message(state.agent_participant_id, text, state.maximum_output_bytes),
           :ok <- Session.settle_output(state.session, pending.correlation, message) do
        {:ok, %{state | awaiting_output: nil}}
      else
        _failure -> {:error, :unavailable}
      end
    else
      :ignored
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp message(_participant_id, nil, _maximum), do: {:ok, nil}

  defp message(participant_id, text, maximum),
    do: Message.spoken_assistant(participant_id, text, :speaker, maximum)

  defp identity(command),
    do: {command.id, command.connection_id, command.correlation_id, command.participant_id}
end
