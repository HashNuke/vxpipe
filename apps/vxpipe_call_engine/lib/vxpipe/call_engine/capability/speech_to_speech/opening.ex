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
            {:reply, :ok, started(state, opening)}

          {:ok, _handle} ->
            {:reply, :ok, started(state, opening)}

          error ->
            {:reply, error, state}
        end
    end
  end

  defp started(state, opening) do
    %{
      state
      | opening_started?: true,
        opening_playing?: true,
        fixed_opening?: match?({:fixed, _text}, opening)
    }
  end

  # Google releases a completed fixed-opening waveform even if its transcription
  # is absent. This permits playback settlement, never an invented public text.
  def audio_only?(%{
        provider: Vxpipe.Providers.Google.STSSession,
        output_stt: nil,
        fixed_opening?: true,
        opening_turn: turn,
        active_output: %{
          provider_turn: turn,
          generation_done?: true,
          pending_text: nil,
          fragments: []
        }
      }),
      do: true

  def audio_only?(_state), do: false

  def admitted(%{opening_playing?: true, opening_turn: nil} = state, turn),
    do: %{state | opening_turn: turn}

  def admitted(state, _turn), do: state

  def completed(%{opening_turn: turn} = state, turn),
    do: %{state | opening_playing?: false, opening_turn: nil, fixed_opening?: false}

  def completed(state, _turn), do: state
end
