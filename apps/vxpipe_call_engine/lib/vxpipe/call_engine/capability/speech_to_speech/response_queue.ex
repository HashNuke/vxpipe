defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.ResponseQueue do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{
    Input,
    Output,
    OutputRecognition,
    ResponseOrigins
  }

  alias Vxpipe.CallEngine.Speech.Session

  @max_pending_turns 16

  def admit_response(turn_ref, context, sequence, state) do
    case ResponseOrigins.accepted_fingerprint(state, context) do
      {:ok, fingerprint} ->
        entry = {:response, turn_ref, context, fingerprint, sequence}
        admit_response_entry(entry, state, :back)

      :error ->
        reject_response(turn_ref, state)
    end
  end

  defp admit_response_entry(
         {:response, turn_ref, _context, fingerprint, _sequence} = entry,
         state,
         position
       ) do
    cond do
      not ResponseOrigins.current?(state, fingerprint) ->
        reject_response(turn_ref, state)

      MapSet.size(state.input_turns) > 0 ->
        queue_turn(state, entry, position)

      not is_nil(state.external_activity_origin) ->
        queue_turn(state, entry, position)

      true ->
        admit_reply(turn_ref, state, entry, position)
    end
  end

  def admit_reply(turn_ref, sequence, state),
    do: admit_reply(turn_ref, state, {:legacy, turn_ref, sequence}, :back)

  defp admit_reply(turn_ref, state, entry, position) do
    cond do
      not is_nil(state.active_output) ->
        queue_turn(state, entry, position)

      output_stt_waiting?(state) ->
        queue_turn(state, entry, position)

      true ->
        case Session.admit_output(state.session, turn_ref) do
          {:ok, handle} ->
            sink_turn = inspect(handle.ref)

            output = %{
              output: handle,
              provider_turn: turn_ref,
              owner_sequence: entry_sequence(entry),
              transcript_interval: Input.transcript_interval(state, state.agent_id),
              sink_turn: sink_turn,
              pending_text: nil,
              text_final?: false,
              stt_text: nil,
              stt_segments: OutputRecognition.new(),
              stt_bytes: 0,
              stt_descriptor: if(state.output_stt, do: state.output_stt.descriptor),
              stt_outcome: :in_progress,
              text_deadline: nil,
              text_expires_at: nil,
              generation_done?: false,
              playback_done?: false,
              played_ms: 0
            }

            send(
              state.owner,
              {:vxpipe_sts_turn_started, self(), state.agent_id, turn_ref, entry_sequence(entry)}
            )

            {:noreply, %{state | active_output: output}}

          {:error, :busy} ->
            queue_turn(state, entry, position)

          {:error, _reason} ->
            if response_entry?(entry),
              do: reject_response(turn_ref, state),
              else: {:noreply, state}
        end
    end
  end

  defp queue_turn(state, entry, position) do
    cond do
      Enum.any?(state.pending_turns, &(entry_turn(&1) == entry_turn(entry))) ->
        {:noreply, state}

      length(state.pending_turns) >= @max_pending_turns ->
        if response_entry?(entry),
          do: reject_response(entry_turn(entry), state),
          else: Output.stop_unavailable(:pending_turn_overflow, state)

      true ->
        pending =
          if position == :front,
            do: [entry | state.pending_turns],
            else: state.pending_turns ++ [entry]

        {:noreply, %{state | pending_turns: pending}}
    end
  end

  defp reject_response(turn_ref, state) do
    case Session.reject_response(state.session, turn_ref) do
      :ok -> {:noreply, state}
      {:error, _reason} -> Output.stop_unavailable(:provider_failed, state)
    end
  end

  defp response_entry?({:response, _turn, _context, _fingerprint, _sequence}), do: true
  defp response_entry?(_entry), do: false

  defp entry_turn({:response, turn, _context, _fingerprint, _sequence}), do: turn
  defp entry_turn({:legacy, turn, _sequence}), do: turn

  defp entry_sequence({:response, _turn, _context, _fingerprint, sequence}), do: sequence
  defp entry_sequence({:legacy, _turn, sequence}), do: sequence

  def retire_stale_pending(state) do
    state =
      if not is_nil(state.external_activity_origin) and
           not ResponseOrigins.current?(state, state.external_activity_origin),
         do: %{state | external_activity_origin: nil},
         else: state

    result =
      Enum.reduce_while(state.pending_turns, [], fn entry, kept ->
        if response_entry?(entry) and not ResponseOrigins.current?(state, elem(entry, 3)) do
          case Session.reject_response(state.session, entry_turn(entry)) do
            :ok -> {:cont, kept}
            {:error, _reason} = error -> {:halt, error}
          end
        else
          {:cont, [entry | kept]}
        end
      end)

    if is_list(result),
      do: {:ok, %{state | pending_turns: Enum.reverse(result)}},
      else: result
  end

  def admit_next_pending(%{active_output: nil, pending_turns: [entry | rest]} = state) do
    cond do
      response_entry?(entry) and not ResponseOrigins.current?(state, elem(entry, 3)) ->
        state = %{state | pending_turns: rest}

        case reject_response(entry_turn(entry), state) do
          {:noreply, state} -> admit_next_pending(state)
          result -> result
        end

      output_stt_waiting?(state) ->
        {:noreply, state}

      response_entry?(entry) and MapSet.size(state.input_turns) > 0 ->
        {:noreply, state}

      response_entry?(entry) and not is_nil(state.external_activity_origin) ->
        {:noreply, state}

      response_entry?(entry) ->
        state = %{state | pending_turns: rest}

        case admit_response_entry(entry, state, :front) do
          {:noreply, %{active_output: nil, pending_turns: ^rest} = state} ->
            admit_next_pending(state)

          result ->
            result
        end

      true ->
        gated_admit(entry, %{state | pending_turns: rest})
    end
  end

  def admit_next_pending(state), do: {:noreply, state}

  defp gated_admit(entry, state) do
    if Output.audio_route_permitted?(state, state.human_id, state.agent_id) and not state.held? do
      admit_reply(entry_turn(entry), state, entry, :front)
    else
      {:noreply, state}
    end
  end

  defp output_stt_waiting?(%{output_stt: nil}), do: false
  defp output_stt_waiting?(%{output_stt: %{ready?: ready?}}), do: not ready?
end
