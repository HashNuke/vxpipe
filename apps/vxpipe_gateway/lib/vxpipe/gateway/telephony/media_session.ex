defmodule Vxpipe.Gateway.Telephony.MediaSession do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Command.ParticipantTransferControl
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket}
  alias Vxpipe.Gateway.Media.STSInput
  alias Vxpipe.Gateway.Telephony.MediaSession.Readiness

  alias Vxpipe.Gateway.Telephony.{
    IncomingAudio,
    MediaBinding,
    MediaRouting,
    MediaSessionSetup,
    SourceGate
  }

  @call_timeout 5_000
  @source_request_timeout 5_000

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    GenServer.start_link(__MODULE__, options, name: via(connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec handle_event(pid(), pid(), Event.t()) :: :ok | {:error, term()}
  def handle_event(session, source, %Event{} = event) do
    safe_call(session, {:event, source, event})
  end

  @spec report_transfer_control(pid(), pid(), ParticipantTransferControl.action()) ::
          :ok | {:error, term()}
  def report_transfer_control(session, source, action) when action in [:accept, :media_ready] do
    safe_call(session, {:transfer_control, source, action})
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(session), do: safe_call(session, :snapshot)

  @impl true
  def readiness(session), do: Readiness.readiness(session, :output)

  def prepare_transfer_media(session, attempt_id),
    do: safe_call(session, {:vxpipe_prepare_transfer_media, attempt_id})

  def input_readiness(session), do: Readiness.readiness(session, :input)
  def input_track(session), do: Readiness.input_track(session)

  def speech_to_speech_track(session, track),
    do: safe_call(session, {:speech_to_speech_track, track})

  def readiness_resources(session, options \\ []), do: Readiness.resources(session, options)

  @impl true
  def readiness_binding(%Resource{kind: :media_connection, instance: session}),
    do: readiness(session)

  def readiness_binding(%Resource{kind: :media_input, instance: session}),
    do: input_readiness(session)

  def readiness_binding(_invalid), do: {:error, :unavailable}

  @impl true
  def init(options) do
    socket_owner = Keyword.fetch!(options, :socket_owner)
    binding = Keyword.fetch!(options, :binding)

    monitors = %{
      Process.monitor(socket_owner) => :socket,
      Process.monitor(binding.leg) => :leg
    }

    case MediaSessionSetup.run(options) do
      {:ok, setup} ->
        monitors = Map.put(monitors, setup.attachment.room_monitor, :room)

        {:ok,
         Map.merge(setup, %{
           binding: binding,
           readiness_resource:
             Resource.new(
               :media_connection,
               {:participant, binding.participant_id},
               __MODULE__,
               {binding, socket_owner, Keyword.fetch!(options, :stream_id)},
               binding: Keyword.fetch!(options, :connection_id)
             ),
           connection_id: Keyword.fetch!(options, :connection_id),
           private_media: nil,
           speech_normalizer: nil,
           source_gate: SourceGate.new(),
           source_request: nil,
           sts_input: nil,
           monitors: monitors,
           reported_transfer_controls: MapSet.new(),
           transfer_acceptance_ready?: false,
           socket_owner: socket_owner,
           stream_id: Keyword.fetch!(options, :stream_id)
         })}

      {:error, _reason} ->
        {:stop, :media_attachment_failed}
    end
  end

  @impl true
  def handle_call({:speech_to_speech_track, track}, _from, state) do
    case STSInput.prepare(state.attachment, track, state.sts_input, :telephony) do
      {:ok, output, input} -> {:reply, {:ok, output}, %{state | sts_input: input}}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_prepare_transfer_media, attempt_id}, _from, state) do
    options = [
      engine: state.engine,
      supervisor: state.child_supervisor,
      input_pipeline: state.media_pipelines.room_ingress,
      input_options: [track_id: state.stream_id],
      output: state.audio_output
    ]

    case Vxpipe.Gateway.Media.PrivateMedia.prepare(state, attempt_id, options) do
      {:ok, receipt, state} -> {:reply, {:ok, receipt}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
      {:stop, reason} -> {:stop, :shutdown, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_handoff_gate, action, scope}, {caller, _}, state) do
    case Vxpipe.Gateway.Media.HandoffGate.control(action, scope, caller, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:vxpipe_connection_readiness, _from, state) do
    binding =
      Vxpipe.Gateway.Media.ConnectionReadiness.binding(
        state,
        __MODULE__,
        Readiness.binding(state),
        state.audio_output
      )

    {:reply, {:ok, binding}, state}
  end

  def handle_call(:readiness_binding, _from, state) do
    {:reply, {:ok, Readiness.binding(state)}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     {:ok,
      Map.take(state, [
        :attachment,
        :audio_output,
        :connection_id,
        :room_audio_egress,
        :room_audio_ingress,
        :transfer_acceptance_ready?,
        :stream_id
      ])}, state}
  end

  def handle_call({:vxpipe_sts_source_hold, scope}, from, state) do
    source_request(:hold, scope, from, state)
  end

  def handle_call({:vxpipe_sts_source_arm, scope}, from, state) do
    source_request(:arm, scope, from, state)
  end

  def handle_call({:event, source, _event}, _from, %{socket_owner: socket_owner} = state)
      when source != socket_owner do
    {:reply, {:error, :wrong_media_source}, state}
  end

  def handle_call(
        {:transfer_control, source, _action},
        _from,
        %{socket_owner: socket_owner} = state
      )
      when source != socket_owner do
    {:reply, {:error, :wrong_media_source}, state}
  end

  def handle_call(
        {:transfer_control, source, action},
        _from,
        %{socket_owner: source} = state
      ) do
    case transfer_control_outcome(action, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:event, source, %Event{kind: :media, stream_id: stream_id}},
        _from,
        %{socket_owner: source, stream_id: stream_id, handoff_gate: %{held?: true}} = state
      ),
      do: {:reply, :ok, state}

  def handle_call(
        {:event, source,
         %Event{kind: :media, stream_id: stream_id, media: %MediaPacket{}} = event},
        _from,
        %{socket_owner: source, stream_id: stream_id} = state
      ) do
    if SourceGate.admitted?(state.source_gate, event.media.source_epoch) do
      frame = audio_frame(state.binding, event)

      case normalizer(state, frame) do
        {:ok, speech_normalizer, state} ->
          {result, input} =
            state.engine
            |> IncomingAudio.deliver(
              state.attachment,
              state.room_audio_ingress,
              frame,
              speech_normalizer,
              state.sts_input
            )

          {:reply, normalize_delivery(result), %{state | sts_input: input}}

        _failure ->
          {:reply, {:error, :media_unavailable}, state}
      end
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:event, _source, _event}, _from, state) do
    {:reply, {:error, :unsupported_media_event}, state}
  end

  @impl true
  def handle_info(
        {:vxpipe_sts_source_hold_ack, token, result},
        %{source_request: %{kind: :hold, token: token} = request} = state
      ),
      do: settle_source_request(result, request, state)

  def handle_info(
        {:vxpipe_sts_source_arm_ack, token, result},
        %{source_request: %{kind: :arm, token: token} = request} = state
      ),
      do: settle_source_request(result, request, state)

  def handle_info(
        {:vxpipe_sts_source_timeout, token},
        %{source_request: %{token: token} = request} = state
      ) do
    GenServer.reply(request.from, {:error, :source_unavailable})
    {:noreply, %{state | source_request: nil}}
  end

  def handle_info(
        {:vxpipe_transfer_acceptance_ready, attempt_id},
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          }
        } = state
      ),
      do: {:noreply, %{state | transfer_acceptance_ready?: true}}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{handoff_gate: %{monitor: monitor}} = state
      ),
      do: {:stop, :shutdown, state}

  def handle_info({:DOWN, monitor, :process, _process, _reason}, %{monitors: monitors} = state)
      when is_map_key(monitors, monitor) do
    {:stop, :normal, state}
  end

  def handle_info(
        {:vxpipe_transfer_pending, monitor, authority, attempt_id},
        %{attachment: %{room_monitor: monitor}} = state
      ) do
    case Vxpipe.Gateway.Media.HandoffGate.pending(
           state,
           authority,
           attempt_id,
           state.audio_output
         ) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:stop, :shutdown, state}
    end
  end

  def handle_info(
        {:vxpipe_startup_speech, monitor},
        %{attachment: %{room_monitor: monitor}} = state
      ) do
    command = %{state.attach_command | deadline: DateTime.add(DateTime.utc_now(), 5, :second)}

    case state.engine.activate_speech_to_text(command) do
      {:ok, ingress} ->
        {:noreply, %{state | attachment: %{state.attachment | media_ingress: ingress}}}

      _failed ->
        {:stop, :shutdown, state}
    end
  end

  def handle_info({:vxpipe_connection_unavailable, _reason}, state) do
    {:stop, :media_unavailable, state}
  end

  def handle_info(
        {:DOWN, reference, :process, _actor, _reason},
        %{private_media: %{monitors: monitors}} = state
      )
      when is_map_key(monitors, reference) do
    {:stop, :media_unavailable, state}
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
    command = %{state.attach_command | deadline: DateTime.add(DateTime.utc_now(), 5, :second)}

    with {:ok, media_ingress} <- state.engine.activate_speech_to_text(command),
         attachment = %{attachment | media_ingress: media_ingress},
         {:ok, routing} <- MediaRouting.start(attachment, routing_options(state)) do
      state = %{
        state
        | attachment: attachment,
          room_audio_egress: routing.room_audio_egress,
          room_audio_ingress: routing.room_audio_ingress
      }

      {:noreply, state}
    else
      {:error, _reason} ->
        {:stop, :media_unavailable, state}
    end
  end

  def handle_info({:vxpipe_event, _event}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  defp source_request(kind, scope, from, %{source_request: nil} = state) do
    with :ok <- authorize_source_request(scope, from, state),
         :ok <- valid_source_scope(kind, scope) do
      token = scope.token
      send(state.socket_owner, source_request_message(kind, scope))

      timer =
        Process.send_after(
          self(),
          {:vxpipe_sts_source_timeout, token},
          @source_request_timeout
        )

      gate = if kind == :hold, do: SourceGate.hold(state.source_gate), else: state.source_gate
      request = %{kind: kind, from: from, token: token, timer: timer}

      {:noreply, %{state | source_gate: gate, source_request: request}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp source_request(_kind, _scope, _from, state),
    do: {:reply, {:error, :source_busy}, state}

  defp authorize_source_request(
         %{attachment: attachment},
         {caller, _},
         %{
           attachment: %ConnectionAttachment{
             admission: :main,
             room_authority: authority,
             room_monitor: monitor
           }
         }
       )
       when is_pid(authority) and caller == authority and attachment == monitor,
       do: :ok

  defp authorize_source_request(_scope, _from, _state), do: {:error, :unauthorized}

  defp valid_source_scope(:hold, %{token: token, deadline_ms: deadline})
       when is_reference(token) and is_integer(deadline),
       do: :ok

  defp valid_source_scope(:arm, %{token: token, active_epoch: epoch, deadline_ms: deadline})
       when is_reference(token) and is_reference(epoch) and is_integer(deadline),
       do: :ok

  defp valid_source_scope(_kind, _scope), do: {:error, :invalid_source_request}

  defp source_request_message(:hold, %{token: token, deadline_ms: deadline_ms}) do
    {:vxpipe_sts_source_hold, %{reply_to: self(), token: token, deadline_ms: deadline_ms}}
  end

  defp source_request_message(:arm, %{token: token, active_epoch: epoch, deadline_ms: deadline_ms}) do
    {:vxpipe_sts_source_arm,
     %{reply_to: self(), token: token, active_epoch: epoch, deadline_ms: deadline_ms}}
  end

  defp settle_source_request(
         {:ok, %{old_epoch: old_epoch, held_epoch: held_epoch}},
         %{kind: :hold} = request,
         state
       )
       when is_reference(old_epoch) and is_reference(held_epoch) do
    Process.cancel_timer(request.timer)

    receipt = %{
      attachment: state.attachment.room_monitor,
      token: request.token,
      receiver: state.socket_owner,
      old_epoch: old_epoch,
      held_epoch: held_epoch
    }

    GenServer.reply(request.from, {:ok, receipt})
    {:noreply, %{state | source_gate: {:held, old_epoch}, source_request: nil}}
  end

  defp settle_source_request({:ok, epoch}, %{kind: :arm} = request, state)
       when is_reference(epoch) do
    Process.cancel_timer(request.timer)
    GenServer.reply(request.from, {:ok, epoch})
    {:noreply, %{state | source_gate: {:active, epoch}, source_request: nil}}
  end

  defp settle_source_request({:error, reason}, request, state) do
    Process.cancel_timer(request.timer)
    GenServer.reply(request.from, {:error, reason})
    # A failed or ambiguous request leaves the source gate held.
    {:noreply, %{state | source_request: nil}}
  end

  defp settle_source_request(_unexpected, request, state) do
    Process.cancel_timer(request.timer)
    GenServer.reply(request.from, {:error, :invalid_source_response})
    {:noreply, %{state | source_request: nil}}
  end

  defp audio_frame(%MediaBinding{} = binding, %Event{media: %MediaPacket{} = media} = event) do
    %AudioFrame{
      tenant_id: binding.tenant_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: binding.participant_id,
      connection_id: binding.client_state_leg_id,
      track_id: event.stream_id,
      codec: media.codec,
      sample_rate: media.sample_rate,
      channels: media.channels,
      sequence_number: media.sequence_number,
      timestamp: media.timestamp,
      payload: media.payload,
      received_at: media.received_at || System.monotonic_time(:millisecond),
      source_epoch: media.source_epoch
    }
  end

  defp normalize_delivery(:ok), do: :ok
  defp normalize_delivery(:drop), do: :ok
  defp normalize_delivery(:unavailable), do: {:error, :media_unavailable}

  defp normalizer(%{attachment: %{media_ingress: nil}} = state, _frame),
    do: {:ok, nil, %{state | speech_normalizer: nil}}

  defp normalizer(
         %{
           attachment: %{media_ingress: ingress},
           speech_normalizer: %{ingress: ingress, value: value}
         } = state,
         _frame
       ),
       do: {:ok, value, state}

  defp normalizer(%{attachment: %{media_ingress: ingress}} = state, frame) do
    with {:ok, target} <- Ingress.media_format(ingress),
         {:ok, value} <- IncomingAudio.new_normalizer(frame, target) do
      {:ok, value, %{state | speech_normalizer: %{ingress: ingress, value: value}}}
    end
  end

  defp transfer_control_command(state, attempt_id, action) do
    ParticipantTransferControl.new(
      tenant_id: state.binding.tenant_id,
      actor_id: state.actor_id,
      room_id: state.binding.room_id,
      incarnation_id: state.binding.incarnation_id,
      participant_id: state.binding.participant_id,
      connection_id: state.connection_id,
      attempt_id: attempt_id,
      action: action,
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    )
  end

  defp transfer_control_outcome(action, state) do
    cond do
      MapSet.member?(state.reported_transfer_controls, action) ->
        {:ok, state}

      match?(
        %ConnectionAttachment{admission: :transfer_preparation},
        state.attachment
      ) ->
        submit_transfer_control(action, state)

      true ->
        {:error, :transfer_not_pending}
    end
  end

  defp submit_transfer_control(action, state) do
    with {:ok, command} <-
           transfer_control_command(state, state.attachment.transfer_attempt_id, action),
         :ok <- state.engine.participant_transfer_control(command) do
      reported = MapSet.put(state.reported_transfer_controls, action)
      ready? = action != :accept and state.transfer_acceptance_ready?
      {:ok, %{state | reported_transfer_controls: reported, transfer_acceptance_ready?: ready?}}
    else
      {:error, %Vxpipe.CallEngine.Error{code: :participant_transfer_not_ready}} -> {:ok, state}
      error -> error
    end
  end

  defp routing_options(state) do
    [
      child_supervisor: state.child_supervisor,
      connection_id: state.connection_id,
      engine: state.engine,
      identity: state.identity,
      output_sink: state.audio_output,
      media_pipelines: state.media_pipelines,
      socket_owner: state.socket_owner,
      stream_id: state.stream_id
    ]
  end

  defp safe_call(server, message) do
    GenServer.call(server, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :media_session_not_found}
  end

  defp via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telephony_media_session, connection_id}}}
  end
end
