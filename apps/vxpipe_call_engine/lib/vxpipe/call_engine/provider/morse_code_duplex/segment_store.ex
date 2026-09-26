defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.SegmentStore do
  @moduledoc "Indexes the Morse provider's admitted output segments."

  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  def new_segment(turn_ref) do
    %{
      turn_ref: turn_ref,
      output_ref: nil,
      fragments: [],
      queue: [],
      queue_bytes: 0,
      awaiting: nil,
      yielded?: false,
      closed?: false,
      completed?: false
    }
  end

  def find_segment_by_turn(state, turn_ref) do
    Enum.find_value(state.segments, :error, fn {seg_ref, segment} ->
      if segment.turn_ref == turn_ref, do: {:ok, seg_ref, segment}, else: nil
    end)
  end

  def find_segment_by_output(state, output_ref) do
    Enum.find_value(state.segments, :error, fn {seg_ref, segment} ->
      if segment.output_ref == output_ref, do: {:ok, seg_ref, segment}, else: nil
    end)
  end

  def put_segment(state, seg_ref, segment),
    do: %{state | segments: Map.put(state.segments, seg_ref, segment)}

  def delete_segment(state, seg_ref),
    do: %{state | segments: Map.delete(state.segments, seg_ref)}

  def drain_all(state) do
    Enum.reduce(Map.keys(state.segments), state, fn seg_ref, state ->
      drain_segment(state, seg_ref)
    end)
  end

  defp drain_segment(state, seg_ref) do
    case Map.fetch(state.segments, seg_ref) do
      :error ->
        state

      {:ok, %{yielded?: true} = segment} ->
        maybe_complete_segment(state, seg_ref, segment)

      {:ok, %{awaiting: nil, output_ref: output_ref} = segment} when is_reference(output_ref) ->
        case segment.queue do
          [pcm | rest] ->
            case Channel.submit(state.channel, output_ref, pcm) do
              {:ok, credit} ->
                put_segment(state, seg_ref, %{
                  segment
                  | queue: rest,
                    queue_bytes: segment.queue_bytes - byte_size(pcm),
                    awaiting: credit
                })

              _failure ->
                put_segment(state, seg_ref, %{
                  segment
                  | queue: [],
                    queue_bytes: 0,
                    closed?: true,
                    completed?: true
                })
            end

          [] ->
            maybe_complete_segment(state, seg_ref, segment)
        end

      _other ->
        state
    end
  end

  defp maybe_complete_segment(
         state,
         seg_ref,
         %{completed?: true, output_ref: output_ref} = segment
       )
       when is_reference(output_ref) do
    _ =
      Event.emit(state.channel, :output_transcript,
        turn_ref: segment.turn_ref,
        text: "",
        final: true
      )

    _ =
      Event.emit(state.channel, :output_completed,
        turn_ref: segment.turn_ref,
        request_ref: output_ref
      )

    delete_segment(state, seg_ref)
  end

  defp maybe_complete_segment(state, _seg_ref, _segment), do: state
end
