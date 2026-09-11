defmodule Vxpipe.Gateway.Telephony.MediaPipelineSet do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.Telnyx.{
    AudioEgressPipeline,
    AudioIngressPipeline,
    AudioOutputPipeline
  }

  @enforce_keys [:direct_output, :room_egress, :room_ingress]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          direct_output: module(),
          room_egress: module(),
          room_ingress: module()
        }

  @spec resolve(atom()) :: {:ok, t()} | {:error, :unsupported_media_provider}
  def resolve(:telnyx) do
    {:ok,
     %__MODULE__{
       direct_output: AudioOutputPipeline,
       room_egress: AudioEgressPipeline,
       room_ingress: AudioIngressPipeline
     }}
  end

  def resolve(_provider), do: {:error, :unsupported_media_provider}
end
