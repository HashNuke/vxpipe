defmodule Vxpipe.Gateway.WebRTC.Connection.SourceAudio do
  @moduledoc false

  alias ExRTP.Packet
  alias ExWebRTC.PeerConnection
  alias Vxpipe.Gateway.WebRTC.IncomingAudio

  def source(
        {:vxpipe_webrtc_source, receiver, epoch, received_at,
         {:ex_webrtc, peer, {:rtp, track_id, _rid, %Packet{} = packet}}},
        %{source_receiver: receiver, source_epoch: epoch, peer_connection: peer} = state
      )
      when is_integer(received_at) do
    if held?(state),
      do: {:noreply, state},
      else: forward(track_id, packet, received_at, epoch, state)
  end

  def source(_message, state), do: {:noreply, state}

  def peer(
        {:ex_webrtc, _peer, {:rtp, _track, _rid, _packet}},
        %{source_receiver: receiver} = state
      )
      when is_pid(receiver),
      do: {:noreply, state}

  def peer(
        {:ex_webrtc, _peer, {:rtp, _track, _rid, _packet}},
        %{handoff_gate: %{held?: true}} = state
      ),
      do: {:noreply, state}

  def peer(
        {:ex_webrtc, peer, {:rtp, track_id, _rid, %Packet{} = packet}},
        %{peer_connection: peer} = state
      ),
      do: forward(track_id, packet, System.monotonic_time(:millisecond), nil, state)

  def peer(_message, state), do: {:noreply, state}

  def track_codecs(peer_connection, track_id) do
    peer_connection
    |> PeerConnection.get_transceivers()
    |> Enum.find(fn transceiver -> transceiver.receiver.track.id == track_id end)
    |> case do
      nil -> %{}
      transceiver -> Map.new(transceiver.codecs, &{&1.payload_type, &1})
    end
  end

  defp held?(state), do: match?(%{held?: true}, Map.get(state, :handoff_gate))

  defp forward(track_id, packet, received_at, epoch, state) do
    state = ensure_track_codecs(track_id, state)
    codec = state.audio_tracks |> Map.get(track_id, %{}) |> Map.get(packet.payload_type)

    case IncomingAudio.forward_connection(codec, track_id, packet, state,
           received_at: received_at,
           source_epoch: epoch
         ) do
      {result, state} when result in [:ok, :drop] -> {:noreply, state}
      {:unavailable, state} -> {:stop, :shutdown, state}
    end
  end

  defp ensure_track_codecs(track_id, state) do
    if Map.has_key?(state.audio_tracks, track_id) do
      state
    else
      %{
        state
        | audio_tracks:
            Map.put(state.audio_tracks, track_id, track_codecs(state.peer_connection, track_id))
      }
    end
  end
end
