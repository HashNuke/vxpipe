defmodule Vxpipe.CallEngine.Diagnostics.CapturePacket do
  @moduledoc "Bounded transient audio, probability and timing evidence; excludes text and arbitrary metadata."
  alias Vxpipe.CallEngine.Media.AudioFrame
  @frame_keys Map.keys(AudioFrame.__struct__())
  @frame_fields length(@frame_keys)
  @maximum_integer 9_223_372_036_854_775_807

  def charge(packet) do
    if valid?(packet),
      do: {:ok, 2 * :erlang.external_size(packet) + 512},
      else: {:error, :invalid_evidence}
  end

  @doc false
  def copy({:audio, %AudioFrame{codec: :opus, activity_pcm: %{payload: pcm}} = frame}),
    do: copy({:audio, %{frame | codec: :linear16, payload: pcm, activity_pcm: nil}})

  def copy({:audio, frame}) do
    {:audio,
     %{
       frame
       | tenant_id: :binary.copy(frame.tenant_id),
         room_id: :binary.copy(frame.room_id),
         incarnation_id: :binary.copy(frame.incarnation_id),
         participant_id: :binary.copy(frame.participant_id),
         connection_id: :binary.copy(frame.connection_id),
         track_id: :binary.copy(frame.track_id),
         payload: :binary.copy(frame.payload)
     }}
  end

  def copy(packet), do: packet

  defp valid?({:audio, %AudioFrame{codec: :linear16, channels: 1, activity_pcm: nil} = frame})
       when map_size(frame) == @frame_fields do
    Enum.all?(@frame_keys, &Map.has_key?(frame, &1)) and valid_audio?(frame)
  end

  defp valid?({:audio, %AudioFrame{codec: :opus, channels: 1, activity_pcm: decoded} = frame})
       when map_size(frame) == @frame_fields and is_map(decoded) and map_size(decoded) == 4 do
    case decoded do
      %{payload: pcm, timestamp: timestamp, sample_rate: rate, channels: 1}
      when is_binary(pcm) and timestamp == frame.timestamp and rate == frame.sample_rate and
             is_binary(frame.payload) and byte_size(frame.payload) > 0 and
             byte_size(frame.payload) + byte_size(pcm) <= 131_072 ->
        valid?({:audio, %{frame | codec: :linear16, payload: pcm, activity_pcm: nil}})

      _ ->
        false
    end
  end

  defp valid?({:probabilities, epoch, first_sample, probabilities, observed_at}) do
    unsigned?(epoch) and unsigned?(first_sample) and signed?(observed_at) and
      probabilities?(probabilities, 32)
  end

  defp valid?({:reset, epoch, reason, observed_at}) do
    unsigned?(epoch) and signed?(observed_at) and
      reason in [
        :provider_turn_settled,
        :source_replaced,
        :audio_gap,
        :inference_failed,
        :partial_start
      ]
  end

  defp valid?({:acoustic_boundary, epoch, kind, sample, offset, confirmed, uncertainty, reason}) do
    unsigned?(epoch) and kind in [:speech_started, :speech_ended] and unsigned?(sample) and
      offset?(confirmed) and
      reason in [nil, :partial_start, :clock_uncertain, :unobserved_audio, :before_run] and
      ((offset?(offset) and offset <= confirmed and unsigned?(uncertainty)) or
         (offset == nil and uncertainty == nil and reason not in [nil, :partial_start]))
  end

  defp valid?({:provider_landmark, generation, turn, kind, observed_at, samples}) do
    is_reference(generation) and is_reference(turn) and signed?(observed_at) and
      unsigned?(samples) and
      kind in [:provider_text_commit, :provider_end_evidence, :adapter_end_emission]
  end

  defp valid?(_packet), do: false

  defp valid_audio?(frame) do
    Enum.all?(
      [
        frame.tenant_id,
        frame.room_id,
        frame.incarnation_id,
        frame.participant_id,
        frame.connection_id,
        frame.track_id
      ],
      &identifier?/1
    ) and
      frame.sample_rate in [8_000, 16_000, 48_000] and
      unsigned?(frame.sequence_number) and unsigned?(frame.timestamp) and
      signed?(frame.received_at) and
      (is_reference(frame.source_epoch) or is_nil(frame.source_epoch)) and
      is_binary(frame.payload) and byte_size(frame.payload) in 2..131_072 and
      rem(byte_size(frame.payload), 2) == 0
  end

  defp probabilities?([], remaining), do: remaining < 32

  defp probabilities?([value | rest], remaining)
       when remaining > 0 and is_number(value) and value >= 0 and value <= 1,
       do: probabilities?(rest, remaining - 1)

  defp probabilities?(_values, _remaining), do: false
  defp offset?(value), do: is_integer(value) and value in 0..604_800_000_000
  defp identifier?(value), do: is_binary(value) and byte_size(value) in 1..256
  defp unsigned?(value), do: is_integer(value) and value in 0..@maximum_integer

  defp signed?(value),
    do: is_integer(value) and value in (-@maximum_integer - 1)..@maximum_integer
end
