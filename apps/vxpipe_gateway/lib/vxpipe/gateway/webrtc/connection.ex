defmodule Vxpipe.Gateway.WebRTC.Connection do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias ExRTP.Packet
  alias ExWebRTC.{DataChannel, MediaStreamTrack, PeerConnection, SessionDescription}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.WebRTC.Connection.Readiness

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.Gateway.RTVI.{ToolProjection, TurnState}

  alias Vxpipe.Gateway.WebRTC.{
    ConnectionPeerSupervisor,
    IncomingAudio,
    SmallWebRTCSignalling,
    TransferSideband
  }

  alias Vxpipe.Gateway.RTVI.Codec, as: RTVICodec

  @call_timeout 10_000
  @command_timeout_seconds 5
  @peer_left_grace_ms 250

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    GenServer.start_link(__MODULE__, options, name: via(:connection, connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def negotiate(connection_id, %SessionDescription{} = offer) do
    call(connection_id, {:negotiate, offer})
  end

  def add_ice_candidates(connection_id, candidates) when is_list(candidates) do
    call(connection_id, {:add_ice_candidates, candidates})
  end

  def prepare_transfer_media(connection_id, attempt_id),
    do: call(connection_id, {:vxpipe_prepare_transfer_media, attempt_id})

  @impl true
  def readiness(connection), do: Readiness.readiness(connection, :output)

  @impl true
  def readiness_binding(%Resource{kind: :media_connection, instance: connection}),
    do: readiness(connection)

  def readiness_binding(%Resource{kind: :media_input, instance: connection}),
    do: input_readiness(connection)

  def readiness_binding(_invalid), do: {:error, :unavailable}

  def input_readiness(connection), do: Readiness.readiness(connection, :input)
  def input_track(connection), do: Readiness.input_track(connection)
  def readiness_resources(connection, options \\ []), do: Readiness.resources(connection, options)

  @impl true
  def init(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    session = Keyword.fetch!(options, :session)
    admission_monitor = if session.admission_owner, do: Process.monitor(session.admission_owner)

    with {:ok, attach_command} <- attach_command(connection_id, session),
         {:ok, peer_connection} <-
           ConnectionPeerSupervisor.start_peer(
             connection_id,
             self(),
             Keyword.fetch!(options, :ice_servers)
           ),
         {:ok, output_track} <- add_output_track(peer_connection),
         {:ok, audio_egress} <-
           ConnectionPeerSupervisor.start_audio_egress(
             connection_id,
             peer_connection,
             output_track.id,
             Keyword.fetch!(options, :maximum_audio_packets),
             tenant_id: session.tenant_id,
             room_id: session.room_id,
             incarnation_id: session.incarnation_id,
             participant_id: session.participant_id
           ),
         {:ok, %ConnectionAttachment{} = attachment} <-
           CallEngine.attach_connection(attach_command, audio_egress),
         {:ok, room_audio_ingress} <-
           ConnectionPeerSupervisor.start_room_audio_ingress(
             connection_id,
             attachment,
             [
               tenant_id: session.tenant_id,
               room_id: session.room_id,
               incarnation_id: session.incarnation_id,
               participant_id: session.participant_id
             ],
             jitter_latency_ms: Keyword.fetch!(options, :audio_jitter_latency_ms)
           ),
         {:ok, room_audio_egress} <-
           ConnectionPeerSupervisor.start_room_audio_egress(
             connection_id,
             attachment,
             [
               tenant_id: session.tenant_id,
               room_id: session.room_id,
               incarnation_id: session.incarnation_id,
               participant_id: session.participant_id
             ],
             audio_egress
           ) do
      {:ok,
       %{
         candidate_gathering_timeout_ms: Keyword.fetch!(options, :candidate_gathering_timeout_ms),
         attachment: attachment,
         private_media: nil,
         attach_command: attach_command,
         audio_egress: audio_egress,
         audio_tracks: %{},
         audio_jitter_latency_ms: Keyword.fetch!(options, :audio_jitter_latency_ms),
         connection_id: connection_id,
         media_readiness_resource:
           Resource.new(
             :media_connection,
             {:participant, session.participant_id},
             __MODULE__,
             {session.tenant_id, session.room_id, session.incarnation_id, session.participant_id,
              peer_connection, output_track.id},
             binding: connection_id
           ),
         negotiation_revision: 0,
         output_track_id: output_track.id,
         peer_connection: peer_connection,
         peer_monitor: Process.monitor(peer_connection),
         room_monitor: attachment.room_monitor,
         room_audio_egress: room_audio_egress,
         room_audio_ingress: room_audio_ingress,
         rtvi_channel_ref: nil,
         rtvi_turn_state: TurnState.new(),
         session: session,
         admission_monitor: admission_monitor,
         sideband_channel_ref: nil,
         transfer_media_ready?: false,
         transfer_preparation_sent?: false,
         transfer_acceptance_ready?: false
       }}
    else
      _error -> {:stop, :connection_attachment_failed}
    end
  end

  @impl true
  def handle_call({:vxpipe_handoff_gate, action, scope}, {caller, _}, state) do
    case Vxpipe.Gateway.Media.HandoffGate.control(action, scope, caller, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_prepare_transfer_media, attempt_id}, _from, state) do
    options = [
      engine: CallEngine,
      supervisor: ConnectionPeerSupervisor,
      input_pipeline: Vxpipe.Gateway.WebRTC.AudioPipeline,
      input_options: [jitter_latency: state.audio_jitter_latency_ms],
      output: state.audio_egress
    ]

    case Vxpipe.Gateway.Media.PrivateMedia.prepare(state, attempt_id, options) do
      {:ok, receipt, state} -> {:reply, {:ok, receipt}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
      {:stop, reason} -> {:stop, :shutdown, {:error, reason}, state}
    end
  end

  def handle_call(:vxpipe_connection_readiness, _from, state) do
    binding =
      Vxpipe.Gateway.Media.ConnectionReadiness.binding(
        state,
        __MODULE__,
        Readiness.binding(state),
        state.audio_egress
      )

    {:reply, {:ok, binding}, state}
  end

  def handle_call(:media_readiness_binding, _from, state) do
    {:reply, {:ok, Readiness.binding(state)}, state}
  end

  def handle_call({:negotiate, offer}, _from, state) do
    reply = negotiate_peer(state.peer_connection, offer, state.candidate_gathering_timeout_ms)
    {:reply, reply, %{state | negotiation_revision: state.negotiation_revision + 1}}
  end

  def handle_call({:add_ice_candidates, candidates}, _from, state) do
    result =
      Enum.reduce_while(candidates, :ok, fn candidate, :ok ->
        case PeerConnection.add_ice_candidate(state.peer_connection, candidate) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, peer_connection, {:track, %MediaStreamTrack{kind: :audio} = track}},
        %{peer_connection: peer_connection} = state
      ) do
    audio_tracks = Map.put(state.audio_tracks, track.id, track_codecs(peer_connection, track.id))
    {:noreply, %{state | audio_tracks: audio_tracks}}
  end

  def handle_info(
        {:ex_webrtc, _peer, {:rtp, _track, _rid, _packet}},
        %{handoff_gate: %{held?: true}} = state
      ),
      do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{handoff_gate: %{monitor: monitor}} = state
      ),
      do: {:stop, :shutdown, state}

  def handle_info(
        {:ex_webrtc, peer_connection, {:rtp, track_id, _rid, %Packet{} = packet}},
        %{peer_connection: peer_connection} = state
      ) do
    state = ensure_track_codecs(track_id, state)
    codec = state.audio_tracks |> Map.get(track_id, %{}) |> Map.get(packet.payload_type)

    case forward_audio(codec, track_id, packet, state) do
      :ok -> {:noreply, state}
      :drop -> {:noreply, state}
      :unavailable -> {:stop, :shutdown, state}
    end
  end

  def handle_info({:ex_webrtc, peer_connection, {:data_channel, %DataChannel{} = channel}}, state)
      when peer_connection == state.peer_connection do
    state = remember_data_channel(channel, state)
    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data, channel_ref, payload}},
        %{peer_connection: peer_connection, rtvi_channel_ref: channel_ref} = state
      ) do
    case RTVICodec.handle(payload) do
      {:reply, reply} -> :ok = PeerConnection.send_data(peer_connection, channel_ref, reply)
      {:command, {:send_text, input}} -> submit_text(input, state)
      :ignore -> :ok
    end

    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data, channel_ref, payload}},
        %{peer_connection: peer_connection, sideband_channel_ref: channel_ref} = state
      ) do
    state_reply(TransferSideband.handle_data(payload, state))
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel_state_change, channel_ref, :open}},
        %{peer_connection: peer_connection, sideband_channel_ref: channel_ref} = state
      ) do
    {:noreply, TransferSideband.channel_opened(state)}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel_state_change, channel_ref, :closed}},
        %{peer_connection: peer_connection} = state
      )
      when channel_ref == state.rtvi_channel_ref or channel_ref == state.sideband_channel_ref do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:connection_state_change, :connected}},
        %{peer_connection: peer_connection} = state
      ) do
    state_reply(TransferSideband.media_connected(state))
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:connection_state_change, connection_state}},
        %{peer_connection: peer_connection} = state
      )
      when connection_state in [:closed, :failed] do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{admission_monitor: monitor} = state
      ),
      do: {:stop, :shutdown, state}

  def handle_info(
        {:DOWN, peer_monitor, :process, _pid, _reason},
        %{peer_monitor: peer_monitor} = state
      ) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:DOWN, room_monitor, :process, _pid, _reason},
        %{room_monitor: room_monitor} = state
      ) do
    case signal_peer_left(state) do
      :sent -> await_peer_disconnect(state)
      :unavailable -> {:stop, :shutdown, state}
    end
  end

  def handle_info(
        {:vxpipe_peer_left_timeout, token},
        %{peer_left_timeout_token: token} = state
      ) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:vxpipe_event, %TextOutput{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    {:noreply, project_turn_event(event, state)}
  end

  def handle_info(
        {:vxpipe_event, %AgentSpeechStarted{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    {:noreply, project_turn_event(event, state)}
  end

  def handle_info(
        {:vxpipe_event, %AgentSpeechProgressed{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    {:noreply, project_turn_event(event, state)}
  end

  def handle_info(
        {:vxpipe_event, %AgentTurnCompleted{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    {:noreply, project_turn_event(event, state)}
  end

  def handle_info(
        {:vxpipe_event, %AgentTurnInterrupted{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    {:noreply, project_turn_event(event, state)}
  end

  def handle_info(
        {:vxpipe_event, %AgentTurnFailed{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    send_event(event, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_event, event},
        %{connection_id: connection_id} = state
      )
      when event.__struct__ in [
             ToolCallStarted,
             ToolCallCompleted,
             ToolCallFailed,
             ToolCallCancelled
           ] and event.connection_id == connection_id do
    send_tool_event(event, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_event, %ParticipantTurnStarted{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    send_event(event, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_event, %ParticipantTranscription{} = event},
        %{attachment: %ConnectionAttachment{admission: :main}, session: session} = state
      )
      when event.tenant_id == session.tenant_id and event.room_id == session.room_id and
             event.incarnation_id == session.incarnation_id do
    send_event(event, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_event, %ParticipantTurnCompleted{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    send_event(event, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_transfer_progress, attempt_id, progress}, state) do
    TransferSideband.send_progress(attempt_id, progress, state)
    send_encoded(RTVICodec.encode_transfer_progress(attempt_id, progress), state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_transfer_active, attempt_id}, state) do
    TransferSideband.send_active(attempt_id, state)
    {:noreply, state}
  end

  def handle_info({:vxpipe_transfer_acceptance_ready, attempt_id}, state) do
    {:noreply, TransferSideband.acceptance_ready(attempt_id, state)}
  end

  def handle_info({:vxpipe_connection_unavailable, _reason}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:DOWN, reference, :process, _actor, _reason},
        %{private_media: %{monitors: monitors}} = state
      )
      when is_map_key(monitors, reference) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:vxpipe_transfer_main_media, attempt_id,
         %ConnectionAttachment{admission: :main} = attachment},
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          }
        } = state
      ) do
    state_reply(TransferSideband.activate_main_media(attempt_id, attachment, state))
  end

  def handle_info({:ex_webrtc, _peer_connection, _event}, state), do: {:noreply, state}

  defp send_event(event, state) do
    with channel_ref when not is_nil(channel_ref) <- state.rtvi_channel_ref,
         {:ok, message} <- RTVICodec.encode_event(event) do
      :ok = PeerConnection.send_data(state.peer_connection, channel_ref, message)
    end
  end

  defp send_tool_event(event, state) do
    with channel_ref when not is_nil(channel_ref) <- state.rtvi_channel_ref,
         {:ok, message} <- ToolProjection.encode(event, state.session.tool_visibility) do
      :ok = PeerConnection.send_data(state.peer_connection, channel_ref, message)
    end
  end

  defp project_turn_event(event, state) do
    {rtvi_turn_state, actions} = TurnState.project(state.rtvi_turn_state, event)
    state = %{state | rtvi_turn_state: rtvi_turn_state}
    Enum.each(actions, &send_turn_action(&1, state))
    state
  end

  defp send_turn_action({:event, event}, state), do: send_event(event, state)

  defp send_turn_action({:spoken_progress, output, event_id, status}, state) do
    send_encoded(RTVICodec.encode_spoken_progress(output, event_id, status), state)
  end

  defp send_turn_action({:interruption_context, event}, state) do
    send_encoded(RTVICodec.encode_interruption_context(event), state)
  end

  defp send_encoded(encoded, state) do
    with channel_ref when not is_nil(channel_ref) <- state.rtvi_channel_ref,
         {:ok, message} <- encoded do
      :ok = PeerConnection.send_data(state.peer_connection, channel_ref, message)
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

  defp track_codecs(peer_connection, track_id) do
    peer_connection
    |> PeerConnection.get_transceivers()
    |> Enum.find(fn transceiver -> transceiver.receiver.track.id == track_id end)
    |> case do
      nil -> %{}
      transceiver -> Map.new(transceiver.codecs, &{&1.payload_type, &1})
    end
  end

  defp forward_audio(nil, _track_id, _packet, _state), do: :drop

  defp forward_audio(codec, track_id, packet, state) do
    IncomingAudio.forward(codec, track_id, packet,
      session: state.session,
      connection_id: state.connection_id,
      attachment: state.attachment,
      room_audio_ingress: state.room_audio_ingress,
      received_at: System.monotonic_time(:millisecond)
    )
  end

  defp call(connection_id, message) do
    case Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id}) do
      [{connection, _value}] -> GenServer.call(connection, message, @call_timeout)
      [] -> {:error, :connection_not_found}
    end
  end

  defp attach_command(connection_id, session) do
    AttachConnection.new(
      tenant_id: session.tenant_id,
      actor_id: session.actor_id,
      room_id: session.room_id,
      incarnation_id: session.incarnation_id,
      participant_id: session.participant_id,
      connection_id: connection_id,
      deadline: command_deadline()
    )
  end

  defp submit_text(input, state) do
    result =
      with {:ok, command} <-
             SendText.new(
               tenant_id: state.session.tenant_id,
               actor_id: state.session.actor_id,
               room_id: state.session.room_id,
               incarnation_id: state.session.incarnation_id,
               participant_id: state.session.participant_id,
               connection_id: state.connection_id,
               correlation_id: input.id,
               content: input.content,
               run_immediately: input.run_immediately,
               audio_response: input.audio_response,
               deadline: command_deadline()
             ),
           :ok <- CallEngine.send_text(command) do
        :ok
      end

    case result do
      :ok ->
        :ok

      {:error, %Error{}} ->
        reply = RTVICodec.encode_error_response(input.id, "The text input could not be accepted.")
        :ok = PeerConnection.send_data(state.peer_connection, state.rtvi_channel_ref, reply)
    end
  end

  defp remember_data_channel(%DataChannel{label: "chat", ref: channel_ref}, state) do
    %{state | rtvi_channel_ref: channel_ref}
  end

  defp remember_data_channel(%DataChannel{label: "vxpipe", ref: channel_ref}, state) do
    %{state | sideband_channel_ref: channel_ref}
  end

  defp remember_data_channel(%DataChannel{}, state), do: state

  defp signal_peer_left(%{rtvi_channel_ref: nil}), do: :unavailable

  defp signal_peer_left(state) do
    :ok =
      PeerConnection.send_data(
        state.peer_connection,
        state.rtvi_channel_ref,
        SmallWebRTCSignalling.encode_peer_left()
      )

    :sent
  catch
    :exit, _reason -> :unavailable
  end

  defp await_peer_disconnect(state) do
    token = make_ref()
    Process.send_after(self(), {:vxpipe_peer_left_timeout, token}, @peer_left_grace_ms)
    {:noreply, Map.put(state, :peer_left_timeout_token, token)}
  end

  defp state_reply({:ok, state}), do: {:noreply, state}
  defp state_reply({:stop, state}), do: {:stop, :shutdown, state}

  defp command_deadline do
    DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)
  end

  defp negotiate_peer(peer_connection, offer, gathering_timeout_ms) do
    with :ok <- PeerConnection.set_remote_description(peer_connection, offer),
         {:ok, answer} <- PeerConnection.create_answer(peer_connection),
         :ok <- PeerConnection.set_local_description(peer_connection, answer),
         :ok <- await_candidate_gathering(peer_connection, gathering_timeout_ms),
         %SessionDescription{} = local_description <-
           PeerConnection.get_local_description(peer_connection) do
      {:ok, local_description}
    end
  end

  defp add_output_track(peer_connection) do
    track = MediaStreamTrack.new(:audio)

    case PeerConnection.add_track(peer_connection, track) do
      {:ok, _sender} -> {:ok, track}
      {:error, _reason} = error -> error
    end
  end

  defp await_candidate_gathering(peer_connection, timeout_ms) do
    receive do
      {:ex_webrtc, ^peer_connection, {:ice_gathering_state_change, :complete}} -> :ok
    after
      timeout_ms -> :ok
    end
  end

  defp via(:connection, connection_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id}}}
  end
end
