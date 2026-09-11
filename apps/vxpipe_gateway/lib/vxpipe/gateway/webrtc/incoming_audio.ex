defmodule Vxpipe.Gateway.WebRTC.IncomingAudio do
  @moduledoc false

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.WebRTC.{AudioFrame, RoomAudioIngress}

  @spec forward(
          RTPCodecParameters.t() | nil,
          ExWebRTC.MediaStreamTrack.id(),
          Packet.t(),
          keyword()
        ) ::
          :ok | :drop | :unavailable
  def forward(nil, _track_id, %Packet{}, _options), do: :drop

  def forward(%RTPCodecParameters{} = codec, track_id, %Packet{} = packet, options) do
    result =
      with {:ok, frame} <-
             AudioFrame.from_rtp(
               Keyword.fetch!(options, :session),
               Keyword.fetch!(options, :connection_id),
               track_id,
               codec,
               packet,
               Keyword.fetch!(options, :received_at)
             ) do
        deliver(frame, options)
      end

    classify(result)
  end

  defp deliver(frame, options) do
    attachment = Keyword.fetch!(options, :attachment)

    results = [
      deliver_speech_audio(attachment, frame),
      RoomAudioIngress.push(Keyword.get(options, :room_audio_ingress), frame)
    ]

    cond do
      Enum.any?(results, &fatal_audio_result?/1) -> :unavailable
      Enum.any?(results, &(&1 == :ok)) -> :ok
      Enum.any?(results, &drop_audio_result?/1) -> :drop
      true -> :unavailable
    end
  end

  defp deliver_speech_audio(%ConnectionAttachment{media_ingress: nil}, _frame), do: :disabled

  defp deliver_speech_audio(%ConnectionAttachment{} = attachment, frame) do
    CallEngine.push_audio(attachment, frame)
  end

  defp classify(result) when result in [:ok, :drop, :unavailable], do: result
  defp classify({:error, reason}) when reason in [:unsupported_codec, :invalid_packet], do: :drop
  defp classify({:error, _reason}), do: :unavailable

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
      :queue_full,
      :stale_frame,
      :stale_policy_interval,
      :stale_policy_revision,
      :stale_sequence,
      :stale_timestamp
    ]
  end
end
