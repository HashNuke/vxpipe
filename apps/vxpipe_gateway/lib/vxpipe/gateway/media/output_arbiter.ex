defmodule Vxpipe.Gateway.Media.OutputArbiter do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, MixedFrame}

  @timeout 5_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def bind_room(output, identity), do: GenServer.call(output, {:bind_room, identity}, @timeout)

  def push_room(output, binding, frame),
    do: GenServer.call(output, {:room, binding, frame}, @timeout)

  @impl true
  def init(options) do
    native = Keyword.fetch!(options, :native_output)
    owner = Keyword.fetch!(options, :owner)

    {:ok,
     %{
       connection_id: Keyword.fetch!(options, :connection_id),
       native: native,
       native_monitor: Process.monitor(native),
       owner: owner,
       owner_monitor: Process.monitor(owner),
       current: nil,
       pending_direct: nil,
       pending_binding: nil,
       binding: nil,
       generation: 0,
       held?: false,
       clearing?: false,
       draining?: false,
       requests: :gen_server.reqids_new()
     }}
  end

  @impl true
  def handle_call({:bind_room, identity}, {caller, _} = from, %{pending_binding: nil} = state) do
    if state.binding, do: Process.demonitor(state.binding.monitor, [:flush])

    binding = %{
      token: make_ref(),
      caller: caller,
      monitor: Process.monitor(caller),
      identity: identity
    }

    state = %{state | binding: binding}

    cond do
      state.clearing? ->
        {:noreply, %{state | pending_binding: {from, binding.token}}}

      state.current && state.current.kind == :room ->
        {:noreply, clear(state, {:bind, from, binding.token}, false)}

      true ->
        {:reply, {:ok, binding.token}, state}
    end
  end

  def handle_call({:bind_room, _}, _from, state), do: {:reply, {:error, :clearing}, state}

  def handle_call({:room, binding, %MixedFrame{} = frame}, {caller, _} = from, state) do
    with :ok <- room_allowed(binding, caller, frame, state) do
      if state.current || state.pending_direct do
        {:reply, :dropped, state}
      else
        token = token()

        audio = %AudioOutputFrame{
          tenant_id: frame.tenant_id,
          room_id: frame.room_id,
          incarnation_id: frame.incarnation_id,
          participant_id: frame.recipient_participant_id,
          connection_id: state.connection_id,
          command_id: token,
          correlation_id: token,
          codec: :linear16,
          sample_rate: frame.sample_rate,
          channels: frame.channels,
          byte_order: :little,
          payload: frame.payload,
          audio_scope: :mixed,
          output_generation: frame.output_generation,
          reply_to: self()
        }

        current = %{kind: :room, token: token, timestamp: frame.timestamp, binding: state.binding}

        {:noreply,
         request(
           %{state | current: current},
           {:vxpipe_audio_output, audio},
           {:room_push, from, token}
         )}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output, %AudioOutputFrame{} = frame}, from, state) do
    with :ok <- direct_allowed(frame, state) do
      cond do
        state.current && state.current.kind == :room && is_nil(state.pending_direct) ->
          {:noreply, %{state | pending_direct: {frame, from}}}

        state.current && state.current.kind == :room ->
          {:reply, {:error, :busy}, state}

        true ->
          {:noreply, push_direct(state, frame, from)}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output_finish, turn, callback}, from, state) do
    if current_turn?(state, turn, callback) && !state.clearing? do
      {:noreply,
       request(state, {:vxpipe_audio_output_finish, state.current.token, self()}, {:reply, from})}
    else
      {:reply, {:error, :wrong_turn}, state}
    end
  end

  def handle_call({:vxpipe_audio_output_interrupt, turn, callback}, from, state) do
    if current_turn?(state, turn, callback) && !state.clearing? do
      {:noreply, clear(state, {:clear, from})}
    else
      {:reply, {:error, :wrong_turn}, state}
    end
  end

  def handle_call(:vxpipe_audio_output_clear, from, %{clearing?: false} = state),
    do: {:noreply, clear(state, {:clear, from})}

  def handle_call(:vxpipe_audio_output_clear, _from, state),
    do: {:reply, {:error, :clearing}, state}

  def handle_call(
        :vxpipe_audio_output_drain,
        from,
        %{current: nil, pending_direct: nil, clearing?: false, draining?: false} = state
      ),
      do:
        {:noreply,
         request(%{state | draining?: true}, :vxpipe_audio_output_drain, {:drain, from})}

  def handle_call(:vxpipe_audio_output_drain, _from, state),
    do: {:reply, {:error, :output_not_drained}, state}

  def handle_call({:vxpipe_audio_output_hold, generation}, from, state) do
    cond do
      state.clearing? ->
        {:reply, {:error, :clearing}, state}

      generation == state.generation && state.held? ->
        {:reply, :ok, state}

      not is_integer(generation) or generation <= state.generation ->
        {:reply, {:error, :stale_output_generation}, state}

      true ->
        {:noreply, clear(%{state | held?: true, generation: generation}, {:hold, from})}
    end
  end

  def handle_call({:vxpipe_audio_output_release, generation}, _from, state) do
    cond do
      generation != state.generation ->
        {:reply, {:error, :stale_output_generation}, state}

      state.current || state.pending_direct || state.clearing? || state.draining? ->
        {:reply, {:error, :output_not_drained}, state}

      true ->
        {:reply, :ok, %{state | held?: false}}
    end
  end

  def handle_call({:vxpipe_bind_recording_egress, _} = message, from, state),
    do: {:noreply, request(state, message, {:reply, from})}

  @impl true
  def handle_info(
        {:vxpipe_audio_playback, native, token, event},
        %{native: native, current: %{token: token}} = state
      ) do
    case {state.current.kind, event} do
      {:room, {:completed, _}} ->
        current = state.current

        send(
          current.binding.caller,
          {:vxpipe_room_output, self(), current.binding.token, current.timestamp}
        )

        {:noreply, advance(%{state | current: nil})}

      {:direct, {:completed, _}} ->
        notify_direct(state.current, event)
        Process.demonitor(state.current.monitor, [:flush])
        {:noreply, %{state | current: nil}}

      {:direct, _} ->
        notify_direct(state.current, event)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state)
      when monitor == state.native_monitor or monitor == state.owner_monitor,
      do: unavailable(state)

  def handle_info({:DOWN, monitor, :process, _, _}, %{binding: %{monitor: monitor}} = state) do
    state = %{state | binding: nil}

    if state.current && state.current.kind == :room && !state.clearing?,
      do: {:noreply, clear(state, :discard, false)},
      else: {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, _, _},
        %{current: %{kind: :direct, monitor: monitor}} = state
      ),
      do: {:noreply, clear(state, :discard)}

  def handle_info({:request_timeout, ref}, state) do
    if Enum.any?(:gen_server.reqids_to_list(state.requests), fn {_, {_, _, token}} ->
         token == ref
       end), do: unavailable(state), else: {:noreply, state}
  end

  def handle_info(message, state) do
    case :gen_server.check_response(message, state.requests, true) do
      {{:reply, reply}, {action, timer, _}, requests} ->
        Process.cancel_timer(timer)
        response(action, reply, %{state | requests: requests})

      {{:error, _}, {_, timer, _}, requests} ->
        Process.cancel_timer(timer)
        unavailable(%{state | requests: requests})

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def format_status(status),
    do: %{
      status
      | state: Map.take(status.state, [:connection_id, :generation, :held?, :clearing?])
    }

  defp response({:reply, from}, reply, state) do
    GenServer.reply(from, reply)
    {:noreply, state}
  end

  defp response({:drain, from}, reply, state) do
    GenServer.reply(from, reply)
    {:noreply, %{state | draining?: false}}
  end

  defp response({:direct_push, from, token, fresh?}, reply, state) do
    GenServer.reply(from, reply)

    if fresh? && reply != :ok && state.current && state.current.token == token do
      {:noreply, clear(state, :discard)}
    else
      {:noreply, state}
    end
  end

  defp response({:room_push, from, token}, :ok, %{current: %{token: token}} = state) do
    GenServer.reply(from, :ok)
    {:noreply, request(state, {:vxpipe_audio_output_finish, token, self()}, :room_finish)}
  end

  defp response({:room_push, from, _}, _reply, state) do
    GenServer.reply(from, {:error, :interrupted})
    {:noreply, state}
  end

  defp response(:room_finish, :ok, state), do: {:noreply, state}
  defp response(:room_finish, {:error, :interrupted}, state), do: {:noreply, state}
  defp response(:room_finish, _, state), do: unavailable(state)

  defp response(action, {:ok, played}, state) do
    case action do
      {:clear, from} -> GenServer.reply(from, {:ok, played})
      {:hold, from} -> GenServer.reply(from, :ok)
      {:bind, from, token} -> GenServer.reply(from, {:ok, token})
      :discard -> :ok
    end

    if state.pending_binding do
      {from, token} = state.pending_binding
      GenServer.reply(from, {:ok, token})
    end

    {:noreply, advance(%{state | clearing?: false, pending_binding: nil})}
  end

  defp response(_, _, state), do: unavailable(state)

  defp room_allowed(binding, caller, frame, state) do
    cond do
      state.draining? ->
        {:error, :draining}

      state.held? ->
        {:error, :held}

      state.clearing? ->
        {:error, :clearing}

      is_nil(state.binding) or state.binding.token != binding or state.binding.caller != caller ->
        {:error, :stale_room_binding}

      frame.output_generation != state.generation ->
        {:error, :stale_output_generation}

      frame.tenant_id != state.binding.identity.tenant_id or
        frame.room_id != state.binding.identity.room_id or
        frame.incarnation_id != state.binding.identity.incarnation_id or
          frame.recipient_participant_id != state.binding.identity.participant_id ->
        {:error, :wrong_recipient}

      frame.sample_rate != 48_000 or frame.channels != 1 or not is_binary(frame.payload) or
          byte_size(frame.payload) != 1_920 ->
        {:error, :invalid_frame}

      true ->
        :ok
    end
  end

  defp direct_allowed(frame, state) do
    cond do
      state.draining? ->
        {:error, :draining}

      frame.codec != :linear16 or frame.sample_rate != 48_000 or frame.channels != 1 or
          frame.byte_order != :little ->
        {:error, :unsupported_audio}

      not is_pid(frame.reply_to) or not is_binary(frame.payload) or byte_size(frame.payload) == 0 ->
        {:error, :invalid_frame}

      state.clearing? ->
        {:error, :clearing}

      frame.output_generation != state.generation ->
        {:error, :stale_output_generation}

      state.held? && frame.audio_scope != :private ->
        {:error, :held}

      frame.connection_id != state.connection_id ->
        {:error, :wrong_connection}

      frame.audio_scope not in [:conversation, :private] ->
        {:error, :invalid_frame}

      state.current && state.current.kind == :direct &&
          !current_turn?(state, frame.correlation_id, frame.reply_to) ->
        {:error, :busy}

      true ->
        :ok
    end
  end

  defp push_direct(state, frame, from) do
    current =
      state.current ||
        %{
          kind: :direct,
          token: token(),
          turn: frame.correlation_id,
          callback: frame.reply_to,
          monitor: Process.monitor(frame.reply_to)
        }

    request(
      %{state | current: current},
      {:vxpipe_audio_output, %{frame | correlation_id: current.token, reply_to: self()}},
      {:direct_push, from, current.token, is_nil(state.current)}
    )
  end

  defp current_turn?(
         %{current: %{kind: :direct, turn: turn, callback: callback}},
         turn,
         callback
       ),
       do: true

  defp current_turn?(_, _, _), do: false

  defp advance(%{pending_direct: {frame, from}} = state),
    do: push_direct(%{state | pending_direct: nil}, frame, from)

  defp advance(state), do: state

  defp notify_direct(current, event),
    do: send(current.callback, {:vxpipe_audio_playback, self(), current.turn, event})

  defp clear(state, action, discard_pending? \\ true) do
    if state.current && state.current.kind == :direct,
      do: Process.demonitor(state.current.monitor, [:flush])

    if state.pending_direct && discard_pending?,
      do: GenServer.reply(elem(state.pending_direct, 1), {:error, :interrupted})

    request(
      %{
        state
        | current: nil,
          pending_direct: if(discard_pending?, do: nil, else: state.pending_direct),
          clearing?: true
      },
      :vxpipe_audio_output_clear,
      action
    )
  end

  defp request(state, message, action) do
    ref = make_ref()
    timer = Process.send_after(self(), {:request_timeout, ref}, @timeout)
    id = :gen_server.send_request(state.native, message)
    %{state | requests: :gen_server.reqids_add(id, {action, timer, ref}, state.requests)}
  end

  defp unavailable(state) do
    send(state.owner, {:vxpipe_connection_unavailable, :audio_output})
    {:stop, :audio_output_unavailable, state}
  end

  defp token, do: "output-#{System.unique_integer([:positive, :monotonic])}"
end
