defmodule Vxpipe.Gateway.Telephony.IncomingAudio do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Media.RoomAudioIngress

  @spec deliver(module(), ConnectionAttachment.t(), pid() | nil, struct()) ::
          :ok | :drop | :unavailable
  def deliver(engine, %ConnectionAttachment{} = attachment, room_audio_ingress, frame) do
    results = [
      deliver_speech_audio(engine, attachment, frame),
      RoomAudioIngress.push(room_audio_ingress, frame)
    ]

    cond do
      Enum.any?(results, &fatal_audio_result?/1) -> :unavailable
      Enum.any?(results, &(&1 == :ok)) -> :ok
      Enum.any?(results, &drop_audio_result?/1) -> :drop
      true -> :unavailable
    end
  end

  defp deliver_speech_audio(_engine, %ConnectionAttachment{media_ingress: nil}, _frame),
    do: :disabled

  defp deliver_speech_audio(engine, %ConnectionAttachment{} = attachment, frame) do
    engine.push_audio(attachment, frame)
  end

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
