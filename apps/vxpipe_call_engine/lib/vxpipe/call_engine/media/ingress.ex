defmodule Vxpipe.CallEngine.Media.Ingress do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.Ingress.AudioOrigin
  alias Vxpipe.CallEngine.Media.Ingress.Readiness
  alias Vxpipe.CallEngine.MediaPolicy.{Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.Readiness.Resource

  @call_timeout 1_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def readiness(ingress), do: Readiness.readiness(ingress)
  def readiness_resources(ingress), do: Readiness.resources(ingress)
  def readiness_resources(ingress, provider), do: Readiness.resources(ingress, provider)
  def prepare_track(ingress, track), do: Readiness.prepare_track(ingress, track)

  def prepare_track(ingress, track, provider),
    do: Readiness.prepare_track(ingress, track, provider)

  def media_format(ingress), do: Readiness.media_format(ingress)

  @doc """
  Sets an optional STS fanout target for live microphone audio.

  When set, each dispatched frame payload is also forwarded to the STS
  capability as `{:vxpipe_ingress_sts_audio, participant_id, payload}` via a
  non-blocking send. STS admission stays bounded inside the capability and
  never affects the STT dispatch path.
  """
  @spec set_sts_target(pid(), pid() | nil) :: :ok | {:error, :unavailable}
  def set_sts_target(ingress, target)
      when is_pid(ingress) and (is_pid(target) or is_nil(target)) do
    try do
      GenServer.call(ingress, {:set_sts_target, target}, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  @impl true
  def readiness_binding(resource), do: Readiness.readiness_binding(resource)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec push(pid(), AudioFrame.t()) ::
          :ok
          | {:error,
             :media_overloaded
             | :queue_full
             | :stale_frame
             | :unsupported_audio
             | :unavailable
             | :wrong_connection
             | :wrong_track}
  def push(ingress, %AudioFrame{} = frame) do
    try do
      GenServer.call(ingress, {:push, frame}, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  @spec open(pid()) :: :ok | {:error, :unavailable}
  def open(ingress) when is_pid(ingress) do
    try do
      GenServer.call(ingress, :open, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  def open(ingress, source_epoch)
      when is_pid(ingress) and is_reference(source_epoch) do
    try do
      GenServer.call(ingress, {:open_source_epoch, source_epoch}, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  def enable_source_cutover(ingress) when is_pid(ingress) do
    try do
      GenServer.call(ingress, :enable_source_cutover, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  def bind_native_generation(ingress, generation)
      when is_pid(ingress) and (is_reference(generation) or is_nil(generation)) do
    try do
      GenServer.call(ingress, {:bind_native_generation, generation}, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  @spec close(pid()) :: :ok | {:error, :unavailable}
  def close(ingress) when is_pid(ingress) do
    try do
      GenServer.call(ingress, :close, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  @spec bind_audio_origin(pid(), map() | nil) ::
          :ok | {:error, :invalid_audio_origin | :unavailable}
  def bind_audio_origin(ingress, origin) when is_pid(ingress) do
    try do
      GenServer.call(ingress, {:bind_audio_origin, origin}, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  @impl true
  def init(options) do
    capability = Keyword.fetch!(options, :capability)

    {:ok,
     %{
       capability: capability,
       capability_monitor: Process.monitor(capability),
       clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
       consecutive_overflows: 0,
       identity: %{
         tenant_id: Keyword.fetch!(options, :tenant_id),
         room_id: Keyword.fetch!(options, :room_id),
         incarnation_id: Keyword.fetch!(options, :incarnation_id),
         participant_id: Keyword.fetch!(options, :participant_id),
         connection_id: Keyword.fetch!(options, :connection_id)
       },
       opening_input_admission: Keyword.get(options, :input_admission, :open),
       source_cutoff_at: nil,
       source_cutover?: false,
       source_cutover_pending?: false,
       source_epoch: nil,
       native_generation: nil,
       in_flight: nil,
       maximum_age_ms: Keyword.fetch!(options, :maximum_age_ms),
       maximum_bytes: Keyword.fetch!(options, :maximum_bytes),
       maximum_consecutive_overflows: Keyword.fetch!(options, :maximum_consecutive_overflows),
       maximum_frames: Keyword.fetch!(options, :maximum_frames),
       owner: Keyword.get(options, :owner),
       policy: nil,
       policy_demand?: true,
       prepared_track: nil,
       readiness_resource:
         Resource.new(
           :speech_to_text_ingress,
           {:participant, Keyword.fetch!(options, :participant_id)},
           __MODULE__,
           {capability,
            Keyword.take(options, [
              :tenant_id,
              :room_id,
              :incarnation_id,
              :participant_id,
              :connection_id,
              :maximum_age_ms,
              :maximum_bytes,
              :maximum_frames,
              :maximum_consecutive_overflows
            ])},
           binding: Keyword.fetch!(options, :connection_id)
         ),
       queue: :queue.new(),
       track_id: nil,
       total_bytes: 0,
       sts_target: Keyword.get(options, :sts_target),
       activity_agent_id: Keyword.get(options, :activity_agent_id),
       audio_origin: nil
     }}
  end

  @impl true
  def handle_call(:readiness_binding, _from, state) do
    {:reply, {:ok, Readiness.binding(state)}, state}
  end

  def handle_call({:prepare_track, expected, track}, _from, state) do
    with true <- Readiness.binding(state).resource == expected,
         :ok <- Readiness.validate_track_binding(state, track) do
      {:reply, :ok, %{state | prepared_track: track, track_id: track.track_id}}
    else
      false -> {:reply, {:error, :unavailable}, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call(:open, _from, %{opening_input_admission: :open} = state),
    do: {:reply, :ok, state}

  def handle_call(:open, _from, %{source_cutover_pending?: true} = state),
    do: {:reply, {:error, :source_epoch_required}, state}

  def handle_call(:open, _from, state) do
    cutoff =
      if is_binary(state.activity_agent_id),
        do: later_cutoff(state.source_cutoff_at, state.clock.()),
        else: nil

    {:reply, :ok, %{state | opening_input_admission: :open, source_cutoff_at: cutoff}}
  end

  def handle_call(
        {:open_source_epoch, epoch},
        _from,
        %{source_cutover?: true, source_cutover_pending?: true} = state
      ) do
    cutoff = if state.activity_agent_id, do: later_cutoff(state.source_cutoff_at, state.clock.())

    {:reply, :ok,
     %{
       state
       | opening_input_admission: :open,
         source_cutover_pending?: false,
         source_epoch: epoch,
         source_cutoff_at: cutoff
     }}
  end

  def handle_call({:open_source_epoch, _epoch}, _from, state),
    do: {:reply, {:error, :source_cutover_not_pending}, state}

  def handle_call(:enable_source_cutover, _from, state),
    do: {:reply, :ok, %{state | source_cutover?: true}}

  def handle_call(:close, _from, state) do
    {:reply, :ok,
     %{
       state
       | opening_input_admission: :closed,
         audio_origin: nil,
         queue: :queue.new(),
         in_flight: nil,
         total_bytes: 0,
         source_cutoff_at: nil,
         source_cutover_pending?: state.source_cutover?,
         source_epoch: nil,
         native_generation: nil
     }}
  end

  def handle_call({:bind_native_generation, generation}, _from, state) do
    {:reply, :ok, %{state | native_generation: generation}}
  end

  def handle_call({:bind_audio_origin, origin}, _from, state) do
    if AudioOrigin.valid?(origin, state.activity_agent_id) do
      state =
        if state.audio_origin == origin do
          state
        else
          cutoff =
            if is_map(origin),
              do: later_cutoff(state.source_cutoff_at, state.clock.()),
              else: state.source_cutoff_at

          %{
            state
            | audio_origin: origin,
              queue: :queue.new(),
              in_flight: nil,
              total_bytes: 0,
              source_cutoff_at: cutoff
          }
        end

      {:reply, :ok, state}
    else
      {:reply, {:error, :invalid_audio_origin}, state}
    end
  end

  def handle_call({:set_sts_target, target}, _from, state)
      when is_pid(target) or is_nil(target) do
    {:reply, :ok, %{state | sts_target: target}}
  end

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, _from, state) do
    case Snapshot.prepare(snapshot, state.policy) do
      {:ok, snapshot} ->
        demand? =
          SpeechToTextDemand.required?(
            snapshot,
            state.identity.participant_id,
            state.activity_agent_id
          )

        source_origin_changed? = source_origin_changed?(state, snapshot, demand?)
        previous_origin = state.audio_origin
        previous_generation = state.native_generation

        state =
          if state.policy != nil and state.policy_demand? == demand? and
               not SpeechToTextDemand.activity_authority_changed?(
                 state.policy,
                 snapshot,
                 state.identity.participant_id,
                 state.activity_agent_id
               ) and
               Snapshot.interval(state.policy, :speech_to_text, state.identity.participant_id) ==
                 Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id) and
               not source_origin_changed? do
            %{state | policy: snapshot}
          else
            install_policy(state, snapshot, demand?, source_origin_changed?)
          end

        if source_origin_changed? do
          send(
            state.owner,
            {:vxpipe_stt_source_origin_invalidated, self(), state.identity, previous_origin,
             snapshot.revision, previous_generation}
          )
        end

        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, _invalid}, _from, state) do
    {:reply, {:error, :invalid_policy}, state}
  end

  def handle_call({:push, frame}, _from, state) do
    cond do
      not same_connection?(frame, state.identity) ->
        {:reply, {:error, :wrong_connection}, state}

      not input_open?(state) ->
        {:reply, :ok, state}

      not source_epoch_current?(frame, state) ->
        {:reply, {:error, :stale_source_epoch}, state}

      not accepted_track?(frame, state.track_id) ->
        {:reply, {:error, :wrong_track}, state}

      not accepted_format?(frame, state.prepared_track) ->
        {:reply, {:error, :unsupported_audio}, state}

      stale?(frame, state) ->
        {:reply, {:error, :stale_frame}, state}

      full?(frame, state) ->
        handle_overflow(state)

      true ->
        envelope = {frame, delivery_intervals(state), state.audio_origin}
        queue = :queue.in(envelope, state.queue)

        state = %{
          state
          | queue: queue,
            total_bytes: state.total_bytes + byte_size(frame.payload),
            track_id: state.track_id || frame.track_id
        }

        dispatch_if_idle(state)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:dispatch, %{in_flight: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, {frame, intervals, origin}}, queue} ->
        if stale?(frame, state) do
          notify_owner(state.owner, {:dropped, :stale, frame.sequence_number})
          send(self(), :dispatch)

          {:noreply,
           %{
             state
             | queue: queue,
               total_bytes: state.total_bytes - byte_size(frame.payload)
           }}
        else
          reference = make_ref()

          :ok =
            SpeechToText.deliver_audio(
              state.capability,
              self(),
              reference,
              frame,
              AudioOrigin.delivery_intervals(intervals, origin)
            )

          forward_sts_audio(state, frame)

          in_flight = %{
            bytes: byte_size(frame.payload),
            reference: reference,
            sequence_number: frame.sequence_number
          }

          {:noreply, %{state | in_flight: in_flight, queue: queue}}
        end

      {:empty, _queue} ->
        {:noreply, state}
    end
  end

  def handle_info(:dispatch, state), do: {:noreply, state}

  def handle_info(
        {:vxpipe_stt_audio_result, capability, reference, sequence_number, :ok},
        %{
          capability: capability,
          in_flight: %{reference: reference, sequence_number: sequence_number} = in_flight
        } = state
      ) do
    notify_owner(state.owner, {:delivered, sequence_number})

    state = %{
      state
      | consecutive_overflows: 0,
        in_flight: nil,
        total_bytes: state.total_bytes - in_flight.bytes
    }

    dispatch_if_idle(state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_stt_audio_result, capability, reference, sequence_number,
         {:error, :policy_denied}},
        %{
          capability: capability,
          in_flight: %{reference: reference, sequence_number: sequence_number} = in_flight
        } = state
      ) do
    notify_owner(state.owner, {:dropped, :policy, sequence_number})

    state = %{
      state
      | in_flight: nil,
        total_bytes: state.total_bytes - in_flight.bytes
    }

    dispatch_if_idle(state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_stt_audio_result, capability, reference, _sequence_number, {:error, _reason}},
        %{capability: capability, in_flight: %{reference: reference}} = state
      ) do
    {:stop, :capability_unavailable, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, capability, _reason},
        %{capability: capability, capability_monitor: monitor} = state
      ) do
    {:stop, :capability_unavailable, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_overflow(state) do
    consecutive_overflows = state.consecutive_overflows + 1
    state = %{state | consecutive_overflows: consecutive_overflows}

    if consecutive_overflows >= state.maximum_consecutive_overflows do
      :ok = SpeechToText.fail(state.capability, :media_overloaded)
      {:stop, :media_overloaded, {:error, :media_overloaded}, state}
    else
      {:reply, {:error, :queue_full}, state}
    end
  end

  defp dispatch_if_idle(%{in_flight: nil}), do: send(self(), :dispatch)
  defp dispatch_if_idle(_state), do: :ok

  defp full?(frame, state) do
    total_frames = :queue.len(state.queue) + if(state.in_flight == nil, do: 0, else: 1)

    total_frames >= state.maximum_frames or
      state.total_bytes + byte_size(frame.payload) > state.maximum_bytes
  end

  defp stale?(frame, state) do
    state.clock.() - frame.received_at > state.maximum_age_ms or
      (state.source_cutoff_at != nil and frame.received_at <= state.source_cutoff_at)
  end

  defp later_cutoff(nil, current), do: current
  defp later_cutoff(previous, current), do: max(previous, current)

  defp input_open?(state) do
    state.opening_input_admission == :open and state.policy_demand? and
      AudioOrigin.current?(
        state.audio_origin,
        state.policy,
        state.identity.participant_id,
        state.activity_agent_id
      )
  end

  defp delivery_intervals(%{policy: nil}), do: nil

  defp delivery_intervals(state) do
    source = state.identity.participant_id

    %{
      speech_to_text: Snapshot.interval(state.policy, :speech_to_text, source),
      input: Snapshot.interval(state.policy, :audio_input, source),
      output: Snapshot.interval(state.policy, :audio_output, source)
    }
  end

  defp install_policy(state, snapshot, demand?, source_origin_changed?) do
    origin =
      if not source_origin_changed? and
           AudioOrigin.current?(
             state.audio_origin,
             snapshot,
             state.identity.participant_id,
             state.activity_agent_id
           ),
         do: state.audio_origin

    %{
      state
      | consecutive_overflows: 0,
        in_flight: nil,
        policy: snapshot,
        policy_demand?: demand?,
        queue: :queue.new(),
        total_bytes: 0,
        audio_origin: origin,
        opening_input_admission:
          if(source_origin_changed? and state.source_cutover?,
            do: :closed,
            else: state.opening_input_admission
          ),
        source_cutover_pending?:
          (source_origin_changed? and state.source_cutover?) or state.source_cutover_pending?,
        source_epoch:
          if(source_origin_changed? and state.source_cutover?, do: nil, else: state.source_epoch),
        native_generation:
          if(source_origin_changed? and state.source_cutover?,
            do: nil,
            else: state.native_generation
          ),
        source_cutoff_at:
          if(source_origin_changed? and state.source_cutover?,
            do: nil,
            else: state.source_cutoff_at
          )
    }
  end

  defp source_origin_changed?(
         %{source_cutover?: true, policy: %Snapshot{} = previous, activity_agent_id: agent} =
           state,
         %Snapshot{} = current,
         demand?
       ) do
    source = state.identity.participant_id

    state.policy_demand? != demand? or
      Snapshot.interval(previous, :speech_to_text, source) !=
        Snapshot.interval(current, :speech_to_text, source) or
      Snapshot.interval(previous, :audio_input, source) !=
        Snapshot.interval(current, :audio_input, source) or
      Snapshot.interval(previous, :audio_output, source) !=
        Snapshot.interval(current, :audio_output, source) or
      activity_authority_changed?(previous, current, source, agent)
  end

  defp source_origin_changed?(_state, _snapshot, _demand?), do: false

  defp activity_authority_changed?(previous, current, source, agent) when is_binary(agent),
    do: SpeechToTextDemand.activity_authority_changed?(previous, current, source, agent)

  defp activity_authority_changed?(_previous, _current, _source, _agent), do: false

  defp source_epoch_current?(_frame, %{source_cutover?: false}), do: true
  defp source_epoch_current?(_frame, %{source_epoch: nil}), do: true

  defp source_epoch_current?(frame, %{source_epoch: epoch}),
    do: frame.source_epoch == epoch

  defp same_connection?(frame, identity) do
    frame.tenant_id == identity.tenant_id and
      frame.room_id == identity.room_id and
      frame.incarnation_id == identity.incarnation_id and
      frame.participant_id == identity.participant_id and
      frame.connection_id == identity.connection_id
  end

  defp accepted_track?(frame, nil),
    do: is_binary(frame.track_id) and byte_size(frame.track_id) > 0

  defp accepted_track?(frame, track_id), do: frame.track_id == track_id

  defp accepted_format?(_frame, nil), do: true

  defp accepted_format?(frame, track),
    do:
      frame.codec == track.codec and frame.sample_rate == track.sample_rate and
        frame.channels == track.channels

  defp notify_owner(owner, message) when is_pid(owner) do
    send(owner, {:vxpipe_media_ingress, self(), message})
  end

  defp notify_owner(_owner, _message), do: :ok

  defp forward_sts_audio(%{sts_target: nil}, _frame), do: :ok

  defp forward_sts_audio(%{sts_target: target} = state, frame)
       when is_pid(target) do
    send(target, {:vxpipe_ingress_sts_audio, state.identity.participant_id, frame.payload})
    :ok
  end
end
