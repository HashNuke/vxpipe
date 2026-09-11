defmodule Vxpipe.Gateway.Telephony.MediaPipelineSet do
  @moduledoc false

  @enforce_keys [:direct_output, :playback_clearer, :room_egress, :room_ingress]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          direct_output: module(),
          playback_clearer: module(),
          room_egress: module(),
          room_ingress: module()
        }

  @spec resolve(atom()) :: {:ok, t()} | {:error, :unsupported_media_provider}
  def resolve(:telnyx) do
    pipeline_set(
      Vxpipe.Gateway.Telephony.Telnyx.AudioOutputPipeline,
      Vxpipe.Gateway.Media.PlaybackClearer.Noop,
      Vxpipe.Gateway.Telephony.Telnyx.AudioEgressPipeline,
      Vxpipe.Gateway.Telephony.Telnyx.AudioIngressPipeline
    )
  end

  def resolve(:twilio) do
    pipeline_set(
      Vxpipe.Gateway.Telephony.Twilio.AudioOutputPipeline,
      Vxpipe.Gateway.Telephony.Twilio.PlaybackClearer,
      Vxpipe.Gateway.Telephony.Twilio.AudioEgressPipeline,
      Vxpipe.Gateway.Telephony.Twilio.AudioIngressPipeline
    )
  end

  def resolve(_provider), do: {:error, :unsupported_media_provider}

  defp pipeline_set(direct_output, playback_clearer, room_egress, room_ingress) do
    {:ok,
     %__MODULE__{
       direct_output: direct_output,
       playback_clearer: playback_clearer,
       room_egress: room_egress,
       room_ingress: room_ingress
     }}
  end
end
