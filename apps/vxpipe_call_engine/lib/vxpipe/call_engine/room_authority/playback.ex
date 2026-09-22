defmodule Vxpipe.CallEngine.RoomAuthority.Playback do
  @moduledoc "Routes playback evidence to transfer, opening or conversational output."

  alias Vxpipe.CallEngine.{Error, RoomMixer}

  alias Vxpipe.CallEngine.RoomAuthority.{
    AgentOutput,
    ParticipantTransfer,
    OpeningAudio,
    CallerIdle,
    ConnectionLifecycle,
    StartupReadiness
  }

  def handle_text_to_speech_playback(capability, request, status, state) do
    case ParticipantTransfer.playback(capability, request, status, state) do
      {:handled, reply} ->
        reply

      :unhandled ->
        opening_result =
          if OpeningAudio.capability?(state.opening_audio, capability) do
            OpeningAudio.playback(state.opening_audio, request, status)
          else
            :unrelated
          end

        case opening_result do
          {:handled, opening_audio} ->
            continue_after_opening_audio(opening_audio, state)

          :unrelated ->
            state = AgentOutput.playback(capability, request, status, state)

            if status == :completed do
              {:noreply, CallerIdle.reconcile(state)}
            else
              {:noreply, state}
            end
        end
    end
  end

  def handle_asset_opening_audio_playback(worker, request, status, state) do
    case OpeningAudio.asset_playback(state.opening_audio, worker, request, status) do
      {:handled, opening_audio} -> continue_after_opening_audio(opening_audio, state)
      :unrelated -> {:noreply, state}
    end
  end

  defp continue_after_opening_audio(opening_audio, state) do
    state = %{state | opening_audio: opening_audio}

    state =
      if OpeningAudio.admission(opening_audio) == :open and
           (state.startup == nil or state.startup_ready?) do
        if state.room_mixer != nil do
          :ok = RoomMixer.complete_opening(state.room_mixer)
        end

        ConnectionLifecycle.open_inputs(state)
      else
        state
      end

    case StartupReadiness.opening_changed(state) do
      {:ok, state} -> {:noreply, CallerIdle.reconcile(state)}
      {:error, %Error{code: code}} -> {:stop, code, state}
    end
  end
end
