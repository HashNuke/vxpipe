defmodule Vxpipe.Gateway.Media.STSInput do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Media.{AudioFrame, STSIngress}
  alias Vxpipe.Gateway.Telephony.IncomingAudio
  alias Vxpipe.Gateway.WebRTC.SpeechInput

  @track_keys [:track_id, :codec, :sample_rate, :channels]

  def prepare(attachment, track, current, transport) do
    with {:ok, %{ingress: ingress, format: format}} <-
           CallEngine.speech_to_speech_input_configuration(attachment) do
      prepare_input(ingress, track, format, current, transport)
    end
  end

  def push(_attachment, _frame, nil), do: {:disabled, nil}

  def push(attachment, %AudioFrame{} = frame, input) do
    with :ok <- validate_track(frame, input.source),
         {:ok, sequence} <- sequence(frame.sequence_number, input),
         {:ok, converted} <- convert(frame, input) do
      result =
        CallEngine.push_speech_to_speech_audio(attachment, %{
          converted
          | sequence_number: sequence
        })

      {result, %{input | sequence: sequence}}
    else
      {:error, _reason} = error -> {error, input}
    end
  end

  defp prepare_input(
         ingress,
         track,
         _format,
         %{ingress: ingress, source: track, transport: transport} = current,
         transport
       ),
       do: {:ok, current.output, current}

  defp prepare_input(ingress, track, format, _current, transport) do
    with {:ok, output, converter} <- configure(track, format, transport),
         :ok <- STSIngress.prepare_track(ingress, output) do
      {:ok, output,
       %{
         ingress: ingress,
         source: track,
         output: output,
         converter: converter,
         transport: transport,
         sequence: nil
       }}
    end
  end

  defp configure(track, format, :webrtc), do: SpeechInput.configure(track, format)

  defp configure(track, format, :telephony) do
    with {:ok, output} <- IncomingAudio.speech_track(track, format),
         {:ok, converter} <- IncomingAudio.new_normalizer(track, format),
         do: {:ok, output, converter}
  end

  defp convert(frame, %{transport: :webrtc, converter: converter}),
    do: SpeechInput.frame(frame, converter)

  defp convert(frame, %{transport: :telephony, converter: converter}),
    do: IncomingAudio.speech_frame(frame, converter)

  defp validate_track(frame, source) do
    if Map.take(frame, @track_keys) == Map.take(source, @track_keys),
      do: :ok,
      else: {:error, :unsupported_audio}
  end

  # RTP sequences wrap at 16 bits. Preserve a monotonic sequence at the engine
  # boundary and reject reordered packets before mutating the native decoder.
  defp sequence(raw, %{transport: :webrtc, sequence: previous})
       when is_integer(raw) and raw in 0..65_535 and is_integer(previous) do
    delta = raw - rem(previous, 65_536)

    delta =
      cond do
        delta < -32_768 -> delta + 65_536
        delta > 32_768 -> delta - 65_536
        true -> delta
      end

    accept_sequence(previous + delta, previous)
  end

  defp sequence(raw, %{sequence: previous}) when is_integer(raw) and raw >= 0,
    do: accept_sequence(raw, previous)

  defp sequence(_raw, _input), do: {:error, :invalid_packet}

  defp accept_sequence(sequence, nil), do: {:ok, sequence}
  defp accept_sequence(sequence, previous) when sequence > previous, do: {:ok, sequence}
  defp accept_sequence(_sequence, _previous), do: {:error, :stale_sequence}
end
