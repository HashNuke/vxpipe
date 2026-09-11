defmodule Vxpipe.Gateway.WebRTC.RoomAudioIngress.FrameProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.Gateway.WebRTC.PCMFrame
  alias Vxpipe.Gateway.WebRTC.RoomAudioIngress.State

  @spec stale_transport_frame?(Vxpipe.CallEngine.Media.AudioFrame.t(), State.t()) :: boolean()
  def stale_transport_frame?(frame, %State{reject_received_through_ms: cutoff})
      when is_integer(cutoff) do
    not is_integer(frame.received_at) or frame.received_at <= cutoff
  end

  def stale_transport_frame?(_frame, %State{}), do: false

  @spec normalized(PCMFrame.t(), pos_integer(), non_neg_integer()) :: NormalizedFrame.t()
  def normalized(%PCMFrame{} = frame, sequence_number, policy_revision) do
    %NormalizedFrame{
      tenant_id: frame.tenant_id,
      room_id: frame.room_id,
      incarnation_id: frame.incarnation_id,
      source_participant_id: frame.participant_id,
      track_id: frame.track_id,
      sequence_number: sequence_number,
      timestamp: frame.timestamp,
      policy_revision: policy_revision,
      sample_rate: frame.sample_rate,
      channels: frame.channels,
      payload: frame.payload
    }
  end
end
