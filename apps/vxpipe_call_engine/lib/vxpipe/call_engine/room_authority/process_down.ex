defmodule Vxpipe.CallEngine.RoomAuthority.ProcessDown do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.{
    CallerIdle,
    ConnectionLifecycle,
    OpeningAudio,
    ParticipantLifecycle,
    ParticipantTransfer,
    StartupReadiness
  }

  def handle(monitor, reason, state) do
    if StartupReadiness.player_down?(monitor, state) do
      StartupReadiness.reply({:error, :wait_player_unavailable}, state)
    else
      process_down(monitor, reason, state)
    end
  end

  defp process_down(monitor, reason, state) do
    case ParticipantTransfer.worker_down(monitor, reason, state) do
      {:handled, state} ->
        {:noreply, state}

      :unhandled ->
        if OpeningAudio.worker_monitor?(state.opening_audio, monitor) do
          OpeningAudio.failed(state.opening_audio)
          StartupReadiness.failed(state, :opening_audio_unavailable)
          {:stop, :opening_audio_unavailable, state}
        else
          state =
            cond do
              Map.has_key?(state.participant_monitors, monitor) ->
                participant_id = Map.fetch!(state.participant_monitors, monitor)
                state = ParticipantLifecycle.remove(monitor, reason, state)
                ParticipantTransfer.promote_connection_after_source_exit(state, participant_id)

              Map.has_key?(state.connection_monitors, monitor) ->
                connection_id = Map.fetch!(state.connection_monitors, monitor)
                state = ConnectionLifecycle.remove(monitor, reason, state)

                case ParticipantTransfer.connection_down(connection_id, state) do
                  {:handled, state} -> state
                  :unhandled -> state
                end

              Map.has_key?(state.speech_to_text_monitors, monitor) ->
                ConnectionLifecycle.remove_unavailable_speech_to_text(monitor, state)

              state.text_capability != nil and state.text_capability.monitor != nil and
                  state.text_capability.monitor == monitor ->
                ConnectionLifecycle.notify(state.connections, :agent_unavailable)
                %{state | text_capability: nil}

              true ->
                state
            end

          {:noreply, CallerIdle.reconcile(state)}
        end
    end
  end
end
