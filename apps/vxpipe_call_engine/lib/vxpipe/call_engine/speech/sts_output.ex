defmodule Vxpipe.CallEngine.Speech.STSOutput do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Allocation, Event, OutputState, OutputTurn}

  def admit(state, caller, command, turn) do
    cond do
      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      not state.active? or not state.ready_acked? ->
        {:reply, {:error, :not_ready}, state}

      state.descriptor.kind != :sts ->
        {:reply, {:error, :unsupported_operation}, state}

      not is_nil(state.output.request) ->
        {:reply, {:error, :busy}, state}

      command.deadline <= System.monotonic_time(:millisecond) or
          :atomics.compare_exchange(command.token, 1, 0, 1) != :ok ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        handle = %OutputTurn{session: state.allocation, turn_ref: turn, ref: make_ref()}
        output = OutputState.admit_sts(state.output, handle)
        send(state.producer, {:vxpipe_speech_output, self(), turn, handle.ref})
        {:reply, {:ok, handle}, %{state | output: output}}
    end
  end

  def complete(
        %Event{request_ref: reference, turn_ref: turn} = event,
        %{output: %{request: %{kind: :sts, ref: reference, turn_ref: turn}}} = state
      ) do
    with {:ok, output} <- OutputState.complete(state.output, event),
         do: {:ok, event, %{state | output: output}}
  end

  def complete(_event, _state), do: {:error, :stale_request}

  def acknowledge(%{output: %{request: %{kind: :sts, ref: reference}}} = state, reference),
    do: %{
      state
      | output: %{state.output | request: %{state.output.request | terminal_acked?: true}}
    }

  def acknowledge(state, _reference), do: state

  def settle(
        state,
        caller,
        %OutputTurn{session: allocation, ref: reference, turn_ref: turn},
        played
      ) do
    cond do
      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      allocation != state.allocation ->
        {:reply, {:error, :stale_request}, state}

      not Allocation.valid?(allocation) ->
        {:reply, {:error, :closed}, state}

      true ->
        case OutputState.settle_sts(
               state.output,
               reference,
               turn,
               played,
               state.descriptor.format
             ) do
          {:ok, output} -> {:reply, :ok, %{state | output: output}}
          error -> {:reply, error, state}
        end
    end
  end
end
