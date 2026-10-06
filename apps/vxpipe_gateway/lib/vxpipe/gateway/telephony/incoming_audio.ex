defmodule Vxpipe.Gateway.Telephony.IncomingAudio do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Media.{RoomAudioIngress, STSInput}
  alias Vxpipe.CallEngine.Media.PCMResampler
  alias Vxpipe.Gateway.WebRTC.OpusDecoder
  alias Vxpipe.Providers.Twilio.PCMU.Codec

  # Opus decodes natively at these rates; other PCM rates decode at 48 kHz and resample.
  @opus_rates [8_000, 12_000, 16_000, 24_000, 48_000]

  # Speech consumers (STT, speech-to-speech) each request their own mono PCM rate.
  # Carrier audio converts to any positive rate rather than refusing one.
  def speech_track(%{codec: source, sample_rate: source_rate, channels: 1} = track, target)
      when is_map(target) do
    case {source, source_rate, target} do
      {codec, rate, %{codec: codec, sample_rate: rate, channels: 1}} ->
        {:ok, track}

      {source, source_rate, %{codec: :linear16, sample_rate: rate, channels: 1}}
      when (source == :opus or (source == :pcmu and source_rate == 8_000)) and
             is_integer(rate) and rate > 0 ->
        {:ok, %{track | codec: :linear16, sample_rate: rate}}

      _unsupported ->
        {:error, :unsupported_audio}
    end
  end

  def speech_track(_track, _target), do: {:error, :unsupported_audio}

  def new_normalizer(frame, target) do
    with {:ok, _track} <- speech_track(frame, target) do
      case {frame.codec, frame.sample_rate, target.codec, target.sample_rate} do
        {codec, rate, codec, rate} ->
          {:ok, :passthrough}

        {:opus, source, :linear16, rate} when rate in @opus_rates ->
          with {:ok, decoder} <- OpusDecoder.new(rate),
               do: {:ok, {:opus_to_pcm, decoder, source, rate}}

        {:opus, source, :linear16, rate} ->
          with {:ok, decoder} <- OpusDecoder.new(48_000),
               do: {:ok, {:opus_resample, decoder, source, rate}}

        {:pcmu, 8_000, :linear16, 8_000} ->
          {:ok, :pcmu_to_pcm}

        {:pcmu, 8_000, :linear16, 16_000} ->
          {:ok, :pcmu_to_pcm16}

        {:pcmu, 8_000, :linear16, rate} ->
          {:ok, {:pcmu_resample, rate}}
      end
    end
  end

  def speech_frame(%AudioFrame{} = frame, :passthrough), do: {:ok, frame}

  def speech_frame(
        %AudioFrame{codec: :opus, sample_rate: source} = frame,
        {:opus_to_pcm, decoder, source, rate}
      ) do
    with {:ok, payload} <- OpusDecoder.decode(decoder, frame.payload) do
      {:ok,
       %{
         frame
         | codec: :linear16,
           sample_rate: rate,
           timestamp: div(frame.timestamp * rate, source),
           payload: payload
       }}
    end
  end

  def speech_frame(
        %AudioFrame{codec: :opus, sample_rate: source} = frame,
        {:opus_resample, decoder, source, rate}
      ) do
    with {:ok, pcm} <- OpusDecoder.decode(decoder, frame.payload) do
      decoded_timestamp = div(frame.timestamp * 48_000, source)
      {payload, timestamp} = PCMResampler.resample(pcm, decoded_timestamp, 48_000, rate)

      {:ok,
       %{frame | codec: :linear16, sample_rate: rate, timestamp: timestamp, payload: payload}}
    end
  end

  def speech_frame(%AudioFrame{codec: :pcmu, sample_rate: 8_000} = frame, {:pcmu_resample, rate}) do
    with {:ok, pcm} <- Codec.decode(frame.payload) do
      {payload, timestamp} = PCMResampler.resample(pcm, frame.timestamp, 8_000, rate)

      {:ok,
       %{frame | codec: :linear16, sample_rate: rate, timestamp: timestamp, payload: payload}}
    end
  end

  def speech_frame(%AudioFrame{codec: :pcmu, sample_rate: 8_000} = frame, :pcmu_to_pcm) do
    with {:ok, payload} <- Codec.decode(frame.payload),
         do: {:ok, %{frame | codec: :linear16, payload: payload}}
  end

  def speech_frame(%AudioFrame{codec: :pcmu, sample_rate: 8_000} = frame, :pcmu_to_pcm16) do
    with {:ok, payload} <- Codec.decode(frame.payload) do
      {:ok,
       %{
         frame
         | codec: :linear16,
           sample_rate: 16_000,
           timestamp: frame.timestamp * 2,
           payload: double_rate(payload)
       }}
    end
  end

  def speech_frame(_frame, _normalizer), do: {:error, :unsupported_audio}

  @spec deliver(module(), ConnectionAttachment.t(), pid() | nil, struct(), term(), map() | nil) ::
          {:ok | :drop | :unavailable, map() | nil}
  def deliver(
        engine,
        %ConnectionAttachment{} = attachment,
        room_audio_ingress,
        frame,
        normalizer,
        sts_input
      ) do
    {sts_result, sts_input} = STSInput.push(attachment, frame, sts_input)

    results = [
      sts_result,
      deliver_speech_audio(engine, attachment, frame, normalizer),
      RoomAudioIngress.push(room_audio_ingress, frame)
    ]

    result =
      cond do
        Enum.any?(results, &fatal_audio_result?/1) ->
          :unavailable

        Enum.any?(results, &(&1 == :ok)) ->
          :ok

        Enum.any?(results, &drop_audio_result?/1) ->
          :drop

        attachment.admission == :transfer_preparation and
            Enum.all?(results, &(&1 == :disabled)) ->
          :drop

        true ->
          :unavailable
      end

    {result, sts_input}
  end

  defp deliver_speech_audio(
         _engine,
         %ConnectionAttachment{media_ingress: nil},
         _frame,
         _normalizer
       ),
       do: :disabled

  defp deliver_speech_audio(engine, %ConnectionAttachment{} = attachment, frame, normalizer) do
    with {:ok, speech_frame} <- speech_frame(frame, normalizer),
         do: engine.push_audio(attachment, speech_frame)
  end

  defp double_rate(pcm), do: double_rate(pcm, [])

  defp double_rate(<<current::little-signed-16, next::little-signed-16, _::binary>> = pcm, acc) do
    <<_current::little-signed-16, rest::binary>> = pcm

    double_rate(
      rest,
      [<<current::little-signed-16, div(current + next, 2)::little-signed-16>> | acc]
    )
  end

  defp double_rate(<<last::little-signed-16>>, acc),
    do:
      IO.iodata_to_binary(
        Enum.reverse([<<last::little-signed-16, last::little-signed-16>> | acc])
      )

  defp double_rate(<<>>, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp fatal_audio_result?(:ok), do: false
  defp fatal_audio_result?(:disabled), do: false
  defp fatal_audio_result?({:error, reason}), do: not drop_audio_reason?(reason)

  defp drop_audio_result?({:error, reason}), do: drop_audio_reason?(reason)
  defp drop_audio_result?(_result), do: false

  defp drop_audio_reason?(reason) do
    reason in [
      :buffer_full,
      :duplicate_frame,
      :media_overloaded,
      :policy_denied,
      :queue_full,
      :speech_to_speech_unavailable,
      :stale_frame,
      :stale_policy_interval,
      :stale_policy_revision,
      :stale_sequence,
      :stale_timestamp
    ]
  end
end
