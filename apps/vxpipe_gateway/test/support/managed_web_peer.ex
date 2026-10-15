defmodule Vxpipe.Gateway.TestManagedWebPeer do
  @moduledoc false

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}

  def child_spec(options), do: PeerConnection.child_spec(options)

  def offer(peer) do
    :ok = PeerConnection.controlling_process(peer, self())
    {:ok, _} = PeerConnection.add_transceiver(peer, :audio, direction: :sendrecv)
    {:ok, offer} = PeerConnection.create_offer(peer)
    :ok = PeerConnection.set_local_description(peer, offer)
    offer.sdp
  end

  def answer(peer, sdp),
    do: PeerConnection.set_remote_description(peer, %SessionDescription{type: :answer, sdp: sdp})

  def candidate(%ICECandidate{} = candidate) do
    %{
      candidate: candidate.candidate,
      sdp_mid: candidate.sdp_mid,
      sdp_mline_index: candidate.sdp_m_line_index
    }
  end
end
