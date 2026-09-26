defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Transcript do
  @moduledoc "Aligns Morse output words with admitted burst audio."

  alias Vxpipe.CallEngine.Speech.Event

  @doc "Convert word offsets from the current PCM frame into session audio time."
  def due_fragments(due, frame_start_ms, sample_rate) do
    bytes_per_ms = div(sample_rate * 2, 1_000)

    Enum.map(due, fn {text, start_bytes, end_bytes} ->
      %{
        text: text,
        start_ms: max(frame_start_ms + div(start_bytes, bytes_per_ms), 0),
        end_ms: frame_start_ms + div(end_bytes, bytes_per_ms)
      }
    end)
  end

  @doc "Store an early word, or emit it against the already admitted output."
  def accept(state, seg_ref, text, start_ms, end_ms) do
    case Map.fetch(state.segments, seg_ref) do
      {:ok, segment} ->
        fragment = {text, start_ms, end_ms}

        if is_reference(segment.output_ref) do
          emit(state, segment, fragment)
        else
          segment = %{segment | fragments: segment.fragments ++ [fragment]}
          {:ok, %{state | segments: Map.put(state.segments, seg_ref, segment)}}
        end

      :error ->
        {:ok, state}
    end
  end

  @doc "Flush words that arrived before the room admitted their burst."
  def admitted(state, seg_ref) do
    case Map.fetch(state.segments, seg_ref) do
      {:ok, segment} ->
        Enum.reduce_while(segment.fragments, {:ok, state}, fn fragment, {:ok, state} ->
          case emit(state, segment, fragment) do
            {:ok, state} -> {:cont, {:ok, state}}
            {:error, reason, state} -> {:halt, {:error, reason, state}}
          end
        end)

      :error ->
        {:ok, state}
    end
  end

  defp emit(state, segment, {text, start_ms, end_ms}) do
    case Event.emit(state.channel, :output_transcript,
           turn_ref: segment.turn_ref,
           output_ref: segment.output_ref,
           text: text,
           audio_start_ms: start_ms,
           audio_end_ms: end_ms,
           final: false
         ) do
      :ok -> {:ok, state}
      _failure -> {:error, :session_failed, state}
    end
  end
end
