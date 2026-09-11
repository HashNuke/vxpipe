defmodule Vxpipe.Gateway.WebRTC.MainMedia do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Session.Snapshot

  alias Vxpipe.Gateway.WebRTC.{
    ConnectionPeerSupervisor,
    RoomAudioEgress,
    RoomAudioIngress
  }

  @spec activate(
          String.t(),
          ConnectionAttachment.t(),
          Snapshot.t(),
          pid(),
          ExWebRTC.MediaStreamTrack.id(),
          non_neg_integer()
        ) :: {:ok, pid(), pid()} | {:error, term()}
  def activate(
        connection_id,
        %ConnectionAttachment{} = attachment,
        %Snapshot{} = session,
        peer_connection,
        output_track_id,
        jitter_latency_ms
      ) do
    identity = [
      tenant_id: session.tenant_id,
      room_id: session.room_id,
      incarnation_id: session.incarnation_id,
      participant_id: session.participant_id
    ]

    with {:ok, ingress} when is_pid(ingress) <-
           ConnectionPeerSupervisor.start_room_audio_ingress(
             connection_id,
             attachment,
             identity,
             jitter_latency_ms: jitter_latency_ms
           ),
         {:ok, egress} when is_pid(egress) <-
           ConnectionPeerSupervisor.start_room_audio_egress(
             connection_id,
             attachment,
             identity,
             peer_connection,
             output_track_id
           ),
         :ok <- RoomAudioIngress.await_ready(ingress),
         :ok <- RoomAudioEgress.await_ready(egress) do
      {:ok, ingress, egress}
    else
      {:error, reason} -> {:error, reason}
      unavailable -> {:error, {:main_media_unavailable, unavailable}}
    end
  end
end
