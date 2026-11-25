defmodule Vxpipe.CallEngine.RoomAuthority.CallerSpeechRecovery do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, STSSourceCutover, STTAudioAdmission}

  defguard recovery_message?(message)
           when elem(message, 0) in [
                  :caller_recovery_withdrawn,
                  :caller_recovery_bound,
                  :vxpipe_stt_stalled,
                  :caller_recovery_prepared,
                  :caller_recovery_playout,
                  :caller_recovery_expired
                ]

  def handle({:caller_recovery_withdrawn, peer, id}, state),
    do: {:noreply, withdrawn(state, id, peer)}

  def handle({:caller_recovery_bound, peer, id}, state),
    do: {:noreply, bound(state, id, peer)}

  def handle({:vxpipe_stt_stalled, capability, identity, session, turn, offset}, state),
    do: {:noreply, stalled(state, capability, identity, session, turn, offset)}

  def handle({:caller_recovery_prepared, peer, id, token, result}, state),
    do: {:noreply, prepared(state, id, peer, token, result)}

  def handle({:caller_recovery_playout, peer, id, token, result}, state),
    do: {:noreply, playout(state, id, peer, token, result)}

  def handle({:caller_recovery_expired, id, ref}, state),
    do: {:noreply, expired(state, id, ref)}

  def handle(_stale, state), do: {:noreply, state}

  def bound(state, id, peer) do
    case state.connections[id] do
      %{pid: ^peer, speech_to_text: %{capability: capability}} = connection ->
        send(capability, {:caller_recovery_enabled, self(), true})

        case Map.get(connection, :speech_recovery) do
          previous when previous in [nil, :withdrawn] ->
            put_in(state.connections[id], Map.put(connection, :speech_recovery, :eligible))

          _ ->
            state
        end

      _ ->
        state
    end
  end

  def withdrawn(state, id, peer) do
    case state.connections[id] do
      %{pid: ^peer, speech_recovery: previous, speech_to_text: %{capability: capability}} ->
        send(capability, {:caller_recovery_enabled, self(), false})
        cancel_timer(previous)
        set(state, id, :withdrawn)

      _ ->
        state
    end
  end

  def stalled(state, capability, identity, session, turn, offset) do
    with {:ok, id, connection} <-
           ConnectionLifecycle.authorized_speech_to_text(capability, identity, state),
         true <- available?(state, id, connection),
         true <-
           turn == :provider_failed or
             match?(
               %{turn_ref: ^turn, allocation_generation: generation}
               when generation == session.generation,
               connection.speech_to_text.turn
             ) do
      generation = session.generation

      case Map.get(connection, :speech_recovery) do
        :eligible ->
          token = Id.generate(:command)

          episode = %{
            token: token,
            started_ms: System.monotonic_time(:millisecond),
            connection_id: id,
            room_turn_id: connection.speech_to_text.turn && connection.speech_to_text.turn.id,
            turn: turn,
            offset: offset,
            session: session,
            phase: :clearing,
            output_generation: nil,
            replacement: nil,
            hearing_done?: false,
            ready?: false,
            timer: nil
          }

          send(connection.pid, {:prepare_caller_recovery, self(), token})
          set(record(state, id, episode, :triggered), id, arm(episode, id, 5_000))

        %{replacement: ^generation} ->
          exit_to_carrier(
            state,
            id,
            if(turn == :provider_failed, do: :recognizer_failed, else: :repeat_stalled)
          )

        _ ->
          state
      end
    else
      _ -> state
    end
  end

  def prepared(state, id, peer, token, result) do
    with %{pid: ^peer, speech_recovery: %{token: ^token, phase: :clearing} = episode} = connection <-
           state.connections[id],
         true <- available?(state, id, connection) do
      with {:ok, generation} <- result,
           {:ok, replacement} <-
             SpeechToText.replace_stalled(
               connection.speech_to_text.capability,
               episode.session,
               episode.turn,
               episode.offset
             ) do
        send(peer, {:play_caller_recovery, self(), token, :hearing, generation})

        episode = %{
          episode
          | phase: :hearing,
            output_generation: generation,
            replacement: replacement.generation
        }

        set(record(state, id, episode, :hearing_requested), id, episode)
      else
        {:error, reason} when reason in [:stale_stall, :ineligible] -> finish(state, id, episode)
        _ -> exit_to_carrier(state, id, :preparation_failed)
      end
    else
      _ -> state
    end
  end

  def signal(state, id, signal) do
    case state.connections[id] do
      %{speech_recovery: %{phase: :clearing, turn: turn, session: session} = episode}
      when signal.kind == :turn_ended and signal.turn_ref == turn and
             signal.allocation_generation == session.generation ->
        finish(state, id, episode)

      %{speech_recovery: %{replacement: generation} = episode} = connection
      when is_reference(generation) and generation == signal.allocation_generation ->
        if available?(state, id, connection) do
          case signal.kind do
            :connected ->
              if STTAudioAdmission.synchronize(state, id) == :ok,
                do:
                  maybe_repeat(record(state, id, episode, :recognizer_ready), id, %{
                    episode
                    | ready?: true
                  }),
                else: exit_to_carrier(state, id, :ingress_binding_failed)

            :turn_started ->
              send(connection.pid, {:stop_caller_recovery_cue, self(), episode.token})
              cancel_timer(episode)

              set(record(state, id, episode, :repeat_started), id, %{
                episode
                | phase: :speaking,
                  timer: nil
              })

            :turn_ended ->
              finish(record(state, id, episode, :repeat_completed), id, episode)

            _ ->
              state
          end
        else
          finish(state, id, episode)
        end

      _ ->
        state
    end
  end

  def playout(state, id, peer, token, status) do
    case state.connections[id] do
      %{pid: ^peer, speech_recovery: %{token: ^token} = episode} = connection ->
        cond do
          not available?(state, id, connection) ->
            finish(state, id, episode)

          episode.phase == :speaking ->
            state

          status != :completed ->
            exit_to_carrier(state, id, :playout_failed)

          episode.phase == :hearing ->
            maybe_repeat(record(state, id, episode, :hearing_completed), id, %{
              episode
              | hearing_done?: true
            })

          episode.phase == :repeat ->
            set(
              record(state, id, episode, :repeat_prompt_completed),
              id,
              arm(%{episode | phase: :awaiting_repeat}, id, 10_000)
            )

          true ->
            state
        end

      _ ->
        state
    end
  end

  def expired(state, id, ref) do
    case state.connections[id] do
      %{speech_recovery: %{timer: {_, ^ref}} = episode} = connection ->
        if available?(state, id, connection),
          do: exit_to_carrier(state, id, :deadline_expired),
          else: finish(state, id, episode)

      _ ->
        state
    end
  end

  defp maybe_repeat(state, id, %{ready?: true, hearing_done?: true, phase: :hearing} = episode) do
    send(
      state.connections[id].pid,
      {:play_caller_recovery, self(), episode.token, :repeat, episode.output_generation}
    )

    set(
      record(state, id, episode, :repeat_requested),
      id,
      arm(%{episode | phase: :repeat}, id, 5_000)
    )
  end

  defp maybe_repeat(state, id, episode), do: set(state, id, episode)

  defp available?(state, id, connection) do
    not State.conversation_held?(state, connection.participant_id) and
      not STSSourceCutover.private_input_held?(state, id)
  end

  defp exit_to_carrier(state, id, reason) do
    connection = state.connections[id]
    cancel_timer(connection.speech_recovery)
    send(connection.pid, {:vxpipe_connection_unavailable, :speech_to_text_unavailable})
    episode = connection.speech_recovery

    details = %{
      "failed_phase" => Atom.to_string(episode.phase),
      "reason" => Atom.to_string(reason)
    }

    set(record(state, id, episode, :carrier_exit, details), id, :closing)
  end

  defp finish(state, id, episode) do
    cancel_timer(episode)
    send(state.connections[id].pid, {:stop_caller_recovery_cue, self(), episode.token})
    set(state, id, :eligible)
  end

  defp record(state, id, episode, phase, details \\ %{}) do
    recorder =
      Recorder.caller_recovery(
        state.archive_recorder,
        state.connections[id],
        episode,
        phase,
        details
      )

    %{state | archive_recorder: recorder}
  end

  defp set(state, id, episode), do: put_in(state.connections[id].speech_recovery, episode)

  defp arm(episode, id, ms) do
    cancel_timer(episode)
    ref = make_ref()
    timer = Process.send_after(self(), {:caller_recovery_expired, id, ref}, ms)
    %{episode | timer: {timer, ref}}
  end

  defp cancel_timer(%{timer: {timer, _}}), do: Process.cancel_timer(timer)
  defp cancel_timer(_episode), do: :ok
end
