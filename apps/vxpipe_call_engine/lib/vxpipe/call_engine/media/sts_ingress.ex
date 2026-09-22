defmodule Vxpipe.CallEngine.Media.STSIngress do
  @moduledoc """
  Connection-bound STS microphone admission with one outstanding delivery credit.

  Starts closed. Holding or changing policy discards queued audio but retains
  the outstanding credit until the capability acknowledges it. The capability
  must recheck the supplied policy revision before accepting that delivery.
  """

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Resource

  @call_timeout 1_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def push(ingress, %AudioFrame{} = frame), do: call(ingress, {:push, frame})
  def prepare_track(ingress, track), do: call(ingress, {:prepare_track, track})
  def media_format(ingress), do: call(ingress, :media_format)
  def open(ingress), do: call(ingress, :open)
  def hold(ingress), do: call(ingress, :hold)
  def stats(ingress), do: call(ingress, :stats)

  @impl true
  def readiness(ingress), do: call(ingress, :readiness)

  @impl true
  def init(options) do
    limits = %{
      maximum_frames: Keyword.get(options, :maximum_frames, 25),
      maximum_bytes: Keyword.get(options, :maximum_bytes, 32_000),
      maximum_age_ms: Keyword.get(options, :maximum_age_ms, 250),
      delivery_timeout_ms: Keyword.get(options, :delivery_timeout_ms, 1_000)
    }

    if valid_limits?(limits) and valid_format?(Keyword.fetch!(options, :format)),
      do: {:ok, initial_state(options, limits)},
      else: {:stop, :invalid_configuration}
  end

  @impl true
  def handle_call(:media_format, _from, state), do: {:reply, {:ok, state.format}, state}

  def handle_call(:readiness, _from, state) do
    resource = %{
      state.resource
      | configuration: Resource.signature({state.resource.configuration, state.prepared_track}),
        policy_interval: if(state.policy, do: state.policy.revision)
    }

    status = if prepared?(state) and permitted?(state), do: :ready, else: :preparing
    {:reply, {:ok, resource, status}, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       queued: :queue.len(state.queue),
       in_flight?: state.in_flight != nil,
       total_bytes: state.total_bytes,
       dropped: state.dropped
     }, state}
  end

  def handle_call({:prepare_track, track}, _from, state) do
    cond do
      not valid_track?(track, state.format) ->
        {:reply, {:error, :unsupported_audio}, state}

      state.prepared_track not in [nil, track] ->
        {:reply, {:error, :track_already_prepared}, state}

      true ->
        {:reply, :ok, %{state | prepared_track: track}}
    end
  end

  def handle_call(:open, _from, state) do
    if prepared?(state),
      do: {:reply, :ok, dispatch(%{state | open?: true})},
      else: {:reply, {:error, :not_prepared}, state}
  end

  def handle_call(:hold, _from, state),
    do: {:reply, :ok, clear_queue(%{state | open?: false})}

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, _from, state) do
    case Snapshot.prepare(snapshot, state.policy) do
      {:ok, snapshot} -> {:reply, :ok, clear_queue(%{state | policy: snapshot})}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, _invalid}, _from, state),
    do: {:reply, {:error, :invalid_policy}, state}

  def handle_call({:push, frame}, _from, state) do
    cond do
      not same_connection?(frame, state.identity) ->
        {:reply, {:error, :wrong_connection}, state}

      not state.open? ->
        {:reply, :ok, state}

      not permitted?(state) ->
        {:reply, {:error, :policy_denied}, state}

      true ->
        admit(frame, state)
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_sts_input_result, capability, reference, result},
        %{capability: capability, in_flight: %{reference: reference} = delivery} = state
      ) do
    Process.cancel_timer(delivery.timer)

    state = %{
      state
      | in_flight: nil,
        total_bytes: state.total_bytes - delivery.bytes,
        dropped: state.dropped + if(result == :ok, do: 0, else: 1)
    }

    {:noreply, dispatch(state)}
  end

  def handle_info({:input_timeout, reference}, %{in_flight: %{reference: reference}} = state),
    do: {:stop, :input_timeout, state}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor in [state.capability_monitor, state.source_monitor],
      do: {:stop, :normal, state}

  def handle_info(_stale_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_to_speech_ingress)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp initial_state(options, limits) do
    capability = Keyword.fetch!(options, :capability)
    source = Keyword.fetch!(options, :source_connection)
    identity = Keyword.fetch!(options, :identity)
    format = Keyword.fetch!(options, :format)

    Map.merge(limits, %{
      capability: capability,
      capability_monitor: Process.monitor(capability),
      source_monitor: Process.monitor(source),
      identity: identity,
      agent_id: Keyword.fetch!(options, :agent_id),
      format: format,
      prepared_track: nil,
      policy: nil,
      open?: false,
      queue: :queue.new(),
      in_flight: nil,
      total_bytes: 0,
      last_sequence: nil,
      dropped: 0,
      clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
      resource:
        Resource.new(
          :speech_to_speech_ingress,
          {:participant, identity.participant_id},
          __MODULE__,
          {capability, source, identity, format, limits},
          binding: identity.connection_id
        )
    })
  end

  defp valid_limits?(limits) do
    Enum.all?(limits, fn {_key, value} -> is_integer(value) and value > 0 end) and
      limits.delivery_timeout_ms <= 5_000
  end

  defp valid_format?(%{codec: :linear16, sample_rate: rate, channels: 1} = format),
    do: map_size(format) == 3 and is_integer(rate) and rate > 0

  defp valid_format?(_format), do: false

  defp admit(frame, state) do
    case validate_frame(frame, state) do
      :ok ->
        state = %{
          state
          | queue: :queue.in(frame, state.queue),
            total_bytes: state.total_bytes + byte_size(frame.payload),
            last_sequence: frame.sequence_number
        }

        {:reply, :ok, dispatch(state)}

      {:error, _reason} = error ->
        {:reply, error, %{state | dropped: state.dropped + 1}}
    end
  end

  defp validate_frame(frame, state) do
    cond do
      frame.track_id != state.prepared_track.track_id -> {:error, :wrong_track}
      not valid_audio?(frame, state.format) -> {:error, :unsupported_audio}
      stale?(frame, state) -> {:error, :stale_frame}
      not new_sequence?(frame.sequence_number, state.last_sequence) -> {:error, :stale_sequence}
      full?(frame, state) -> {:error, :queue_full}
      true -> :ok
    end
  end

  defp dispatch(%{open?: true, in_flight: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, frame}, queue} -> dispatch_frame(frame, %{state | queue: queue})
      {:empty, _queue} -> state
    end
  end

  defp dispatch(state), do: state

  defp dispatch_frame(frame, state) do
    if permitted?(state) and not stale?(frame, state) do
      reference = make_ref()
      timer = Process.send_after(self(), {:input_timeout, reference}, state.delivery_timeout_ms)
      send(state.capability, {:vxpipe_sts_input, self(), reference, frame, state.policy.revision})

      %{
        state
        | in_flight: %{reference: reference, timer: timer, bytes: byte_size(frame.payload)}
      }
    else
      dispatch(%{
        state
        | total_bytes: state.total_bytes - byte_size(frame.payload),
          dropped: state.dropped + 1
      })
    end
  end

  defp clear_queue(state) do
    %{
      state
      | queue: :queue.new(),
        total_bytes: if(state.in_flight, do: state.in_flight.bytes, else: 0),
        dropped: state.dropped + :queue.len(state.queue)
    }
  end

  defp prepared?(state), do: state.policy != nil and state.prepared_track != nil
  defp permitted?(%{policy: nil}), do: false

  defp permitted?(state) do
    MapSet.member?(state.policy.present_participant_ids, state.identity.participant_id) and
      MapSet.member?(state.policy.present_participant_ids, state.agent_id) and
      Effective.audio_route_permitted?(
        state.policy.effective,
        state.identity.participant_id,
        state.agent_id
      )
  end

  defp same_connection?(frame, identity) do
    frame.tenant_id == identity.tenant_id and frame.room_id == identity.room_id and
      frame.incarnation_id == identity.incarnation_id and
      frame.participant_id == identity.participant_id and
      frame.connection_id == identity.connection_id
  end

  defp valid_track?(%{track_id: id} = track, format),
    do: is_binary(id) and byte_size(id) > 0 and Map.delete(track, :track_id) == format

  defp valid_track?(_track, _format), do: false

  defp valid_audio?(frame, format) do
    frame.codec == :linear16 and frame.codec == format.codec and
      frame.sample_rate == format.sample_rate and frame.channels == 1 and
      is_binary(frame.payload) and byte_size(frame.payload) > 0 and
      rem(byte_size(frame.payload), 2) == 0
  end

  defp stale?(frame, state) do
    not is_integer(frame.received_at) or frame.received_at > state.clock.() or
      state.clock.() - frame.received_at > state.maximum_age_ms
  end

  defp new_sequence?(sequence, last),
    do: is_integer(sequence) and sequence >= 0 and (last == nil or sequence > last)

  defp full?(frame, state) do
    count = :queue.len(state.queue) + if(state.in_flight, do: 1, else: 0)

    count >= state.maximum_frames or
      state.total_bytes + byte_size(frame.payload) > state.maximum_bytes
  end

  defp call(ingress, message) do
    GenServer.call(ingress, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
