defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.OutputSettlement do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{Message, Session}
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.State

  @spec await(State.t()) :: State.t()
  def await(%State{history_mode: :host_settled, current: current} = state)
      when not is_nil(current) do
    %{
      state
      | awaiting_output: pending(current.command, current.correlation, current.proposed_speech)
    }
  end

  def await(%State{} = state), do: state

  def pending(command, correlation, text) do
    %{command: command, correlation: correlation, message: text, status: "queued"}
  end

  def playback_started(%State{awaiting_output: %{command: command} = pending} = state, command_id)
      when command.id == command_id do
    %{state | awaiting_output: Map.put(pending, :status, "playing")}
  end

  def playback_started(state, _command_id), do: state

  def proposed_speech({:ok, %{dialogue: %{agent_mode: :speaker, message: text}}}), do: text
  def proposed_speech({:ok, %{output: text}}) when is_binary(text) and text != "", do: text
  def proposed_speech(_), do: nil

  def in_flight_description(
        %State{awaiting_output: %{message: text, status: status, command: command}},
        %{tool_context: context}
      )
      when is_binary(text) and command.connection_id == context.connection_id and
             command.participant_id == context.source_participant_id do
    # The exact native response remains in provider replay. Bound the additional
    # context independently so an unusually long utterance cannot fill it.
    %{
      "status" => status,
      "message" => String.slice(text, 0, 512),
      "correlation_id" => command.correlation_id
    }
  end

  def in_flight_description(_state, _correlation), do: nil

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
