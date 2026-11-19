defmodule Vxpipe.CallEngine.Diagnostics.ProviderSamples do
  @moduledoc "Prospective correspondence between admitted provider PCM and one captured source."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff
  alias Vxpipe.CallEngine.Media.AudioFrame

  @identities [:tenant_id, :room_id, :incarnation_id, :participant_id, :connection_id, :track_id]
  @maximum_integer 9_223_372_036_854_775_807

  def accept(mapping, %CaptureHandoff{} = handoff, generation, before_samples, frame) do
    if CaptureHandoff.current?(handoff) do
      case position(frame) do
        {:ok, source, first, sequence, samples} ->
          accept_position(
            mapping,
            handoff,
            generation,
            before_samples,
            source,
            first,
            sequence,
            samples
          )

        :error ->
          retire(handoff)
      end
    end
  end

  def accept(_mapping, _handoff, _generation, _before_samples, _frame), do: nil

  def raw(nil, _handoff), do: nil
  def raw(_mapping, %CaptureHandoff{} = handoff), do: retire(handoff)
  def raw(_mapping, _handoff), do: nil

  defp accept_position(
         %{token: token} = mapping,
         %{token: token} = handoff,
         generation,
         before_samples,
         source,
         first,
         sequence,
         samples
       ) do
    if mapping.generation == generation and mapping.source == source and
         mapping.next_provider == before_samples and
         mapping.next_source == first and mapping.next_sequence == sequence do
      %{
        mapping
        | next_provider: before_samples + samples,
          next_source: first + samples,
          next_sequence: sequence + 1
      }
    else
      retire(handoff)
    end
  end

  defp accept_position(
         _old,
         handoff,
         generation,
         before_samples,
         source,
         first,
         sequence,
         samples
       ) do
    case CaptureHandoff.offer(
           handoff,
           {:provider_sample_mapping, generation, before_samples, first}
         ) do
      :ok ->
        {epoch, identities} = source

        %{
          token: handoff.token,
          generation: generation,
          source: {epoch, Enum.map(identities, &:binary.copy/1)},
          next_provider: before_samples + samples,
          next_source: first + samples,
          next_sequence: sequence + 1
        }

      _ ->
        retire(handoff)
    end
  end

  defp position(
         %AudioFrame{
           codec: :linear16,
           sample_rate: 16_000,
           channels: 1,
           activity_pcm: nil,
           payload: payload,
           source_epoch: epoch,
           timestamp: timestamp,
           sequence_number: sequence
         } = frame
       )
       when is_reference(epoch) and is_integer(timestamp) and timestamp in 0..@maximum_integer and
              is_integer(sequence) and sequence in 0..@maximum_integer and is_binary(payload) and
              byte_size(payload) > 0 and rem(byte_size(payload), 2) == 0 do
    identities = Enum.map(@identities, &Map.get(frame, &1))

    if Enum.all?(identities, &(is_binary(&1) and byte_size(&1) in 1..256)),
      do: {:ok, {epoch, identities}, timestamp, sequence, div(byte_size(payload), 2)},
      else: :error
  end

  defp position(_frame), do: :error

  defp retire(handoff) do
    CaptureHandoff.close(handoff)
    nil
  end
end
