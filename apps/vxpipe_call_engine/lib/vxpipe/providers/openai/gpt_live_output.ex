defmodule Vxpipe.Providers.OpenAI.GPTLiveOutput do
  @moduledoc "Admitted, credited GPT-Live audio bursts and aligned spoken text."

  alias Vxpipe.CallEngine.Speech.Duplex.{BurstResponses, OutputSegmenter}
  alias Vxpipe.CallEngine.Speech.{Channel, Event}
  alias Vxpipe.Providers.OpenAI.{GPTLiveFixedOpening, GPTLiveOpening}

  @maximum_queued_bytes 96_000

  def push_pcm(%{fixed_opening: opening} = state, pcm) when not is_nil(opening) do
    case GPTLiveFixedOpening.push_pcm(opening, pcm) do
      {:ok, opening} ->
        {:ok, %{state | fixed_opening: opening}}

      {:verified, verified, rest} ->
        with {:ok, state} <- release_opening(state, verified), do: push_pcm(state, rest)

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def push_pcm(state, pcm) do
    case OutputSegmenter.push_pcm(state.segmenter, pcm) do
      {:error, :buffer_overflow, segmenter} ->
        {:error, :buffer_overflow, %{state | segmenter: segmenter}}

      {segmenter, events} ->
        apply_events(%{state | segmenter: segmenter}, events)
    end
  end

  def fragment(%{fixed_opening: opening} = state, fragment) when not is_nil(opening) do
    case GPTLiveFixedOpening.fragment(opening, fragment) do
      {:ok, opening} -> {:ok, %{state | fixed_opening: opening}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  def fragment(state, fragment) do
    {segmenter, events} = OutputSegmenter.fragment(state.segmenter, fragment)
    apply_events(%{state | segmenter: segmenter}, events)
  end

  def finish(state) do
    {segmenter, events} = OutputSegmenter.finish(state.segmenter)
    apply_events(%{state | segmenter: segmenter}, events)
  end

  def burst?(%{fixed_opening: opening}) when not is_nil(opening),
    do: OutputSegmenter.burst?(opening.segmenter)

  def burst?(state), do: OutputSegmenter.burst?(state.segmenter)

  def idle(state) do
    if burst?(state) do
      silence = :binary.copy(<<0, 0>>, div(state.output_gap_ms * 24_000, 1_000))
      push_pcm(state, silence)
    else
      {:ok, state}
    end
  end

  def schedule_idle(state) do
    if state.output_timer, do: Process.cancel_timer(state.output_timer)
    generation = make_ref()

    if burst?(state) do
      timer = Process.send_after(self(), {:output_idle, generation}, state.output_gap_ms)
      %{state | output_timer: timer, output_generation: generation}
    else
      %{state | output_timer: nil, output_generation: generation}
    end
  end

  defp release_opening(state, verified) do
    state = %{
      state
      | fixed_opening: nil,
        segmenter: verified.segmenter,
        verified_opening_ref: verified.reference,
        unanswered?: false
    }

    with {:ok, state} <- apply_event(state, {:open, verified.reference}) do
      case Map.fetch(state.segments, verified.reference) do
        {:ok, segment} ->
          segment = %{
            segment
            | queue: verified.chunks,
              queue_bytes: verified.bytes,
              fragments: [verified.fragment]
          }

          apply_event(
            put_segment(state, verified.reference, segment),
            {:close, verified.reference}
          )

        :error ->
          {:ok, state}
      end
    end
  end

  def admitted(state, turn_ref, output_ref) do
    {bursts, actions} = BurstResponses.admitted(state.bursts, turn_ref, output_ref)
    apply_actions(%{state | bursts: bursts}, actions)
  end

  def discarded(state, turn_ref) do
    {bursts, actions} = BurstResponses.discarded(state.bursts, turn_ref)
    apply_actions(%{state | bursts: bursts}, actions)
  end

  def credit(state, output_ref, credit) do
    case find_by_output(state, output_ref) do
      {:ok, seg_ref, %{awaiting: ^credit} = segment} ->
        state |> put_segment(seg_ref, %{segment | awaiting: nil}) |> drain_all()

      _other ->
        state
    end
  end

  def interrupt(state, turn_ref) do
    case find_by_turn(state, turn_ref) do
      {:ok, seg_ref, segment} ->
        state =
          put_segment(state, seg_ref, %{segment | yielded?: true, queue: [], queue_bytes: 0})

        {:ok, drain_all(state)}

      :error ->
        {:error, :stale_request}
    end
  end

  defp apply_events(state, events) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, state} ->
      case apply_event(state, event) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp apply_event(state, {:open, seg_ref}) do
    {state, result} = GPTLiveOpening.burst_opened(state, seg_ref)

    case result do
      {:error, :pending_response_overflow} ->
        {:error, :pending_response_overflow, state}

      {bursts, [{:drop_segment, ^seg_ref}]} ->
        {segmenter, _events} = OutputSegmenter.finish(state.segmenter)
        {:ok, %{state | bursts: bursts, segmenter: segmenter}}

      {bursts, [{:announce, turn_ref, index, context}]} ->
        case Event.emit(state.channel, :response_started,
               turn_ref: turn_ref,
               response_index: index,
               response_context: context
             ) do
          :ok ->
            segment = %{
              turn_ref: turn_ref,
              output_ref: nil,
              fragments: [],
              queue: [],
              queue_bytes: 0,
              awaiting: nil,
              yielded?: false,
              completed?: false
            }

            {:ok, %{state | bursts: bursts, segments: Map.put(state.segments, seg_ref, segment)}}

          _failure ->
            {:error, :session_failed, state}
        end
    end
  end

  defp apply_event(state, {:audio, seg_ref, pcm}) do
    case Map.fetch(state.segments, seg_ref) do
      {:ok, %{yielded?: true}} ->
        {:ok, state}

      {:ok, segment} ->
        bytes = segment.queue_bytes + byte_size(pcm)

        if bytes > @maximum_queued_bytes do
          {:error, :buffer_overflow, state}
        else
          segment = %{segment | queue: segment.queue ++ [pcm], queue_bytes: bytes}
          {:ok, state |> put_segment(seg_ref, segment) |> drain_all()}
        end

      :error ->
        {:ok, state}
    end
  end

  defp apply_event(state, {:close, seg_ref}) do
    {bursts, actions} = BurstResponses.burst_closed(state.bursts, seg_ref)
    apply_actions(%{state | bursts: bursts}, actions)
  end

  defp apply_event(%{verified_opening_ref: ref} = state, {:transcript, ref, _text, _start, _end}),
    do: {:error, :session_failed, state}

  defp apply_event(state, {:transcript, seg_ref, text, start_ms, end_ms}) do
    case Map.fetch(state.segments, seg_ref) do
      {:ok, %{output_ref: output_ref} = segment} when is_reference(output_ref) ->
        emit_fragment(state, segment, text, start_ms, end_ms)

      {:ok, segment} ->
        segment = %{segment | fragments: segment.fragments ++ [{text, start_ms, end_ms}]}
        {:ok, put_segment(state, seg_ref, segment)}

      :error ->
        {:ok, state}
    end
  end

  defp apply_event(state, _other), do: {:ok, state}

  defp apply_actions(state, actions) do
    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, state} ->
      case apply_action(state, action) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp apply_action(state, {:admit_segment, seg_ref, output_ref}) do
    {state, events} = admit_segment_audio(state, seg_ref)

    case Map.fetch(state.segments, seg_ref) do
      {:ok, segment} ->
        state = put_segment(state, seg_ref, %{segment | output_ref: output_ref})

        with {:ok, state} <- apply_events(state, events),
             {:ok, state} <- flush_fragments(state, seg_ref) do
          {:ok, drain_all(state)}
        end

      :error ->
        {:ok, state}
    end
  end

  defp apply_action(state, {:complete, turn_ref, _output_ref}) do
    case find_by_turn(state, turn_ref) do
      {:ok, seg_ref, segment} ->
        {:ok, state |> put_segment(seg_ref, %{segment | completed?: true}) |> drain_all()}

      :error ->
        {:ok, state}
    end
  end

  defp apply_action(state, {:complete_empty, turn_ref, output_ref}) do
    with :ok <- Event.emit(state.channel, :interrupted, turn_ref: turn_ref),
         :ok <-
           Event.emit(state.channel, :output_completed,
             turn_ref: turn_ref,
             request_ref: output_ref
           ) do
      {:ok, state}
    else
      _failure -> {:error, :session_failed, state}
    end
  end

  defp apply_action(state, {:drop_segment, seg_ref}) do
    {segmenter, _events} = OutputSegmenter.finish(state.segmenter)
    {:ok, %{state | segmenter: segmenter, segments: Map.delete(state.segments, seg_ref)}}
  end

  defp admit_segment_audio(%{retired_segmenter: %{outputs: outputs}} = state, seg_ref)
       when is_map_key(outputs, seg_ref) do
    {segmenter, events} = OutputSegmenter.admitted(state.retired_segmenter, seg_ref)
    {%{state | retired_segmenter: segmenter}, events}
  end

  defp admit_segment_audio(state, seg_ref) do
    {segmenter, events} = OutputSegmenter.admitted(state.segmenter, seg_ref)
    {%{state | segmenter: segmenter}, events}
  end

  defp emit_fragment(state, segment, text, start_ms, end_ms) do
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

  defp flush_fragments(state, seg_ref) do
    segment = Map.fetch!(state.segments, seg_ref)

    Enum.reduce_while(segment.fragments, {:ok, state}, fn {text, start_ms, end_ms},
                                                          {:ok, state} ->
      case emit_fragment(state, segment, text, start_ms, end_ms) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason, state} -> {:halt, {:error, reason, state}}
      end
    end)
  end

  defp drain_all(state) do
    Enum.reduce(Map.keys(state.segments), state, fn seg_ref, state -> drain(state, seg_ref) end)
  end

  defp drain(state, seg_ref) do
    case Map.fetch(state.segments, seg_ref) do
      {:ok, %{output_ref: output_ref, awaiting: nil} = segment} when is_reference(output_ref) ->
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
                    completed?: true
                })
            end

          [] ->
            maybe_complete(state, seg_ref, segment)
        end

      _other ->
        state
    end
  end

  defp maybe_complete(state, seg_ref, %{completed?: true} = segment) do
    _ =
      Event.emit(state.channel, :output_transcript,
        turn_ref: segment.turn_ref,
        text: "",
        final: true
      )

    _ =
      Event.emit(state.channel, :output_completed,
        turn_ref: segment.turn_ref,
        request_ref: segment.output_ref
      )

    # A completed output on a ready session proves its connection works, so a later loss may
    # reseed again. A replacement that drops before reaching this point still fails.
    reseed_attempted? = state.reseed_attempted? and not state.ready?
    %{state | segments: Map.delete(state.segments, seg_ref), reseed_attempted?: reseed_attempted?}
  end

  defp maybe_complete(state, _seg_ref, _segment), do: state

  defp find_by_turn(state, turn_ref) do
    Enum.find_value(state.segments, :error, fn {seg_ref, segment} ->
      if segment.turn_ref == turn_ref, do: {:ok, seg_ref, segment}
    end)
  end

  defp find_by_output(state, output_ref) do
    Enum.find_value(state.segments, :error, fn {seg_ref, segment} ->
      if segment.output_ref == output_ref, do: {:ok, seg_ref, segment}
    end)
  end

  defp put_segment(state, seg_ref, segment),
    do: %{state | segments: Map.put(state.segments, seg_ref, segment)}
end
