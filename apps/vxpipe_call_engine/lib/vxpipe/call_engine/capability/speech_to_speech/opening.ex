defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Opening do
  @moduledoc "Once-only admission of an engine-owned STS opening."

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.ResponseOrigins

  def start(opening, caller, state) do
    cond do
      caller != state.owner ->
        {:reply, {:error, :not_owner}, state}

      state.held? ->
        {:reply, {:error, :held}, state}

      state.opening_started? ->
        {:reply, {:error, :already_started}, state}

      state.descriptor == nil ->
        {:reply, {:error, :not_ready}, state}

      true ->
        {result, state} = ResponseOrigins.submit(state, {:opening, opening})

        case result do
          :ok ->
            {:reply, :ok, %{state | opening_started?: true, opening_playing?: true}}

          {:ok, _handle} ->
            {:reply, :ok, %{state | opening_started?: true, opening_playing?: true}}

          error ->
            {:reply, error, state}
        end
    end
  end

  def admitted(%{opening_playing?: true, opening_turn: nil} = state, turn),
    do: %{state | opening_turn: turn}

  def admitted(state, _turn), do: state

  def completed(%{opening_turn: turn} = state, turn),
    do: %{state | opening_playing?: false, opening_turn: nil}

  def completed(state, _turn), do: state
end
