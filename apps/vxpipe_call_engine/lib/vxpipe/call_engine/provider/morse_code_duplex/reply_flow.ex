defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.ReplyFlow do
  @moduledoc "Queues and clocks the Morse provider's continuous reply stream."

  alias Vxpipe.CallEngine.Provider.MorseCode.Encoder
  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.Output
  alias Vxpipe.CallEngine.Speech.Duplex.{BurstResponses, OutputSegmenter}

  def next_frame(state) do
    silence = :binary.copy(<<0, 0>>, div(state.frame_bytes, 2))
    {frame, timeline, due} = Output.next_frame(state.timeline, state.frame_bytes, silence)
    {frame, due, %{state | timeline: timeline}}
  end

  def advance(state) do
    %{state | timeline: Output.advance(state.timeline, OutputSegmenter.burst?(state.segmenter))}
  end

  def enqueue(state, reply) do
    with {:ok, intervals} <- Encoder.word_intervals(state.config, reply.text) do
      reply =
        Map.merge(reply, %{
          word_intervals: intervals,
          bytes_per_ms: div(state.config.sample_rate * 2, 1_000),
          pcm: soften_onset(reply.pcm, state.config.sample_rate)
        })

      case Output.enqueue(state.timeline, reply) do
        {:ok, timeline} -> {:ok, advance(%{state | timeline: timeline})}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def yield_current(state) do
    {bursts, []} = BurstResponses.yielded(state.bursts)

    segments =
      Enum.into(state.segments, %{}, fn {seg_ref, segment} ->
        {seg_ref, %{segment | yielded?: true, queue: [], queue_bytes: 0}}
      end)

    %{state | bursts: bursts, timeline: Output.stop(state.timeline), segments: segments}
  end

  def hold(state) do
    state = yield_current(state)
    %{state | timeline: %{state.timeline | queued: []}}
  end

  defp soften_onset(pcm, sample_rate) do
    onset_bytes = div(sample_rate * 2 * 20, 1_000)

    case pcm do
      <<onset::binary-size(onset_bytes), rest::binary>> ->
        softened =
          for <<sample::little-signed-integer-size(16) <- onset>>, into: <<>> do
            <<div(sample, 4)::little-signed-integer-size(16)>>
          end

        softened <> rest

      _short ->
        pcm
    end
  end
end
