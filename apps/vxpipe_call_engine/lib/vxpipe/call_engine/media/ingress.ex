defmodule Vxpipe.CallEngine.Media.Ingress do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.Ingress.Readiness
  alias Vxpipe.CallEngine.MediaPolicy.{Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.Readiness.Resource

  @call_timeout 1_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def readiness(ingress), do: Readiness.readiness(ingress)
  def readiness_resources(ingress), do: Readiness.resources(ingress)
  def prepare_track(ingress, track), do: Readiness.prepare_track(ingress, track)

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
       total_bytes: 0
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

  def handle_call(:open, _from, state) do
    {:reply, :ok, %{state | opening_input_admission: :open}}
  end

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, _from, state) do
    case Snapshot.prepare(snapshot, state.policy) do
      {:ok, snapshot} ->
        demand? = SpeechToTextDemand.required?(snapshot, state.identity.participant_id)

        state =
          if state.policy != nil and
               Snapshot.interval(state.policy, :speech_to_text, state.identity.participant_id) ==
                 Snapshot.interval(snapshot, :speech_to_text, state.identity.participant_id) do
            %{state | policy: snapshot}
          else
            install_policy(state, snapshot, demand?)
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

      not accepted_track?(frame, state.track_id) ->
        {:reply, {:error, :wrong_track}, state}

      not accepted_format?(frame, state.prepared_track) ->
        {:reply, {:error, :unsupported_audio}, state}

      stale?(frame, state) ->
        {:reply, {:error, :stale_frame}, state}

      full?(frame, state) ->
        handle_overflow(state)

      true ->
        queue = :queue.in(frame, state.queue)

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
      {{:value, frame}, queue} ->
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
          :ok = SpeechToText.deliver_audio(state.capability, self(), reference, frame)

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
    state.clock.() - frame.received_at > state.maximum_age_ms
  end

  defp input_open?(state) do
    state.opening_input_admission == :open and state.policy_demand?
  end

  defp install_policy(state, snapshot, demand?) do
    %{
      state
      | consecutive_overflows: 0,
        in_flight: nil,
        policy: snapshot,
        policy_demand?: demand?,
        queue: :queue.new(),
        total_bytes: 0
    }
  end

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
end
