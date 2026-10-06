defmodule Vxpipe.Gateway.Telephony.OutgoingLeg do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Telephony.{Event, Submission}

  alias Vxpipe.Gateway.Telephony.{
    MediaAdmission,
    MediaBinding,
    MediaSupervisor,
    LegUsage,
    OutgoingLegDialer,
    OutgoingLegIdentity,
    IngressIdentity,
    OutgoingLegLifecycle,
    InitialLegLifecycle
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    leg_id = Keyword.fetch!(options, :leg_id)
    service = Keyword.fetch!(options, :service)
    GenServer.start_link(__MODULE__, options, name: via(leg_id, service))
  end

  def child_spec(options) do
    leg_id = Keyword.fetch!(options, :leg_id)

    %{
      id: {__MODULE__, leg_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec await(pid(), timeout()) :: :ok | {:ok, :unknown} | {:error, term()}
  def await(leg, timeout) when is_pid(leg) do
    GenServer.call(leg, :await, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @spec dispatch(pid(), Event.t(), timeout()) :: :ok | {:error, term()}
  def dispatch(leg, %Event{} = event, timeout) when is_pid(leg) do
    GenServer.call(leg, {:event, event}, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @spec disconnect(pid(), timeout()) :: :ok | {:error, :telephony_leg_unavailable}
  def disconnect(leg, timeout) when is_pid(leg) do
    GenServer.call(leg, :disconnect, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  def abandon(leg) when is_pid(leg), do: GenServer.cast(leg, :abandon)

  @impl true
  def init(options) do
    {:ok,
     %{
       leg_id: Keyword.fetch!(options, :leg_id),
       request: Keyword.fetch!(options, :request),
       initial:
         InitialLegLifecycle.new(
           Keyword.fetch!(options, :request),
           Keyword.fetch!(options, :service)
         ),
       pending_media: nil,
       service: Keyword.fetch!(options, :service),
       deadline_ms: Keyword.get(options, :deadline_ms),
       monotonic_clock: Keyword.fetch!(options, :monotonic_clock),
       media_admission: Keyword.fetch!(options, :media_admission),
       media_supervisor: Keyword.get(options, :media_supervisor, MediaSupervisor),
       binding: nil,
       result: nil,
       status: :starting,
       usage: nil,
       usage_options:
         [
           usage_clock: Keyword.fetch!(options, :usage_clock),
           usage_reporter: Keyword.get(options, :usage_reporter)
         ]
         |> Enum.reject(fn {_key, value} -> is_nil(value) end),
       waiters: []
     }, {:continue, :dial}}
  end

  @impl true
  def handle_continue(:dial, state) do
    if is_integer(state.deadline_ms) and state.monotonic_clock.() >= state.deadline_ms,
      do: {:noreply, fail(state, :outbound_connection_unavailable, :failed)},
      else: submit_dial(state)
  end

  defp submit_dial(state) do
    case OutgoingLegDialer.dial(
           state.leg_id,
           state.request,
           state.service,
           state.media_admission,
           self(),
           state.usage_options
         ) do
      {:ok, %Submission{status: :unknown}, usage} ->
        {:noreply, state |> Map.put(:usage, usage) |> succeed(:unknown, nil)}

      {:ok, %Submission{status: :accepted} = submission, usage} ->
        state = %{state | usage: usage}

        case adopt_submission(state, submission) do
          {:ok, binding} -> {:noreply, succeed(state, :accepted, binding)}
          {:error, reason} -> {:noreply, fail(state, reason, :unknown)}
        end

      {:error, reason, usage} ->
        {:noreply, state |> Map.put(:usage, usage) |> fail(reason, :failed)}
    end
  end

  @impl true
  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call(
        :disconnect,
        _from,
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    :ok =
      OutgoingLegLifecycle.end_attempt(
        binding,
        state.service,
        state.leg_id,
        InitialLegLifecycle.cancellation_reason(state)
      )

    {:stop, :normal, :ok, finish_usage(state, :cancelled)}
  end

  def handle_call(:disconnect, _from, %{status: :unknown, initial: initial} = state)
      when initial != nil do
    {:keep, state} = InitialLegLifecycle.cancel(state)
    {:reply, :ok, state}
  end

  def handle_call(:disconnect, _from, %{status: :unknown} = state),
    do: {:stop, :normal, :ok, finish_usage(state, :unknown)}

  def handle_call(:disconnect, _from, state),
    do: {:stop, :normal, :ok, finish_usage(state, :cancelled)}

  def handle_call(
        {:event, %Event{kind: kind} = event},
        _from,
        %{status: :unknown} = state
      )
      when kind in [:outgoing, :answered, :ended] do
    case OutgoingLegIdentity.from_event(
           event,
           state.leg_id,
           state.request,
           state.service,
           self()
         ) do
      {:ok, binding} ->
        case register_and_bind(state, binding) do
          :ok -> handle_adopted_event(event, binding, state)
          {:error, reason} -> {:reply, {:error, reason}, fail(state, reason, :unknown)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:event, %Event{kind: :outgoing} = event},
        _from,
        %{status: :accepted} = state
      ) do
    case OutgoingLegIdentity.from_event(
           event,
           state.leg_id,
           state.request,
           state.service,
           self()
         ) do
      {:ok, binding} when binding == state.binding -> {:reply, :ok, state}
      _mismatch -> {:reply, {:error, :telephony_leg_mismatch}, state}
    end
  end

  def handle_call(
        {:event, %Event{kind: :media_started, stream_id: stream_id} = event},
        {source, _tag},
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    if MediaBinding.matches_event?(binding, event) do
      state = observe_usage(state, event)

      if InitialLegLifecycle.hold_media?(state) do
        {:reply, :ok, %{state | pending_media: {source, stream_id}}}
      else
        {:reply, start_media(state, source, stream_id), state}
      end
    else
      {:reply, {:error, :telephony_leg_mismatch}, state}
    end
  end

  def handle_call(
        {:event, %Event{kind: :media} = event},
        {source, _tag},
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    result =
      if MediaBinding.matches_event?(binding, event) do
        if InitialLegLifecycle.hold_media?(state),
          do: :ok,
          else: MediaSupervisor.handle_event(binding.client_state_leg_id, source, event)
      else
        {:error, :telephony_leg_mismatch}
      end

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: :dtmf, digit: "1"} = event},
        {source, _tag},
        %{binding: %MediaBinding{} = binding, status: :accepted, request: %{purpose: :transfer}} =
          state
      ) do
    result =
      if MediaBinding.matches_event?(binding, event) do
        MediaSupervisor.report_transfer_control(binding.client_state_leg_id, source, :accept)
      else
        {:error, :telephony_leg_mismatch}
      end

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: :dtmf} = event},
        _from,
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      ) do
    result =
      if MediaBinding.matches_event?(binding, event),
        do: :ok,
        else: {:error, :telephony_leg_mismatch}

    {:reply, result, state}
  end

  def handle_call(
        {:event, %Event{kind: kind} = event},
        _from,
        %{binding: %MediaBinding{} = binding, status: :accepted} = state
      )
      when kind in [:answered, :answering_machine, :ended] do
    case OutgoingLegLifecycle.handle(event, binding, state.service, state.leg_id) do
      {:keep, {:error, :telephony_leg_mismatch} = result} ->
        {:reply, result, state}

      {:keep, result} ->
        state = state |> observe_usage(event) |> InitialLegLifecycle.observe(event)
        {media_result, state} = release_pending_media(state)
        {:reply, if(result == :ok, do: media_result, else: result), state}

      {:stop, result} ->
        state =
          state
          |> observe_usage(event)
          |> finish_stopped_usage(event)
          |> InitialLegLifecycle.observe(event)

        {:stop, :normal, result, state}
    end
  end

  def handle_call({:event, _event}, _from, state) do
    {:reply, {:error, :telephony_event_not_supported}, state}
  end

  @impl true
  def handle_cast(:abandon, %{initial: initial} = state) when initial != nil do
    case InitialLegLifecycle.cancel(state) do
      {:keep, state} -> {:noreply, state}
      {:stop, state} -> {:stop, :normal, finish_usage(state, :cancelled)}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{initial: %{room_monitor: monitor}} = state
      ) do
    case InitialLegLifecycle.cancel(state) do
      {:keep, state} -> {:noreply, state}
      {:stop, state} -> {:stop, :normal, finish_usage(state, :cancelled)}
    end
  end

  def handle_info(:retire_unknown, %{initial: %{cancel_pending?: true}} = state),
    do: {:stop, :normal, state |> InitialLegLifecycle.retire() |> finish_usage(:unknown)}

  def handle_info(:retire, %{status: :failed} = state), do: {:stop, :normal, state}
  def handle_info(:retire, state), do: {:noreply, state}

  defp reply_waiters(waiters, result), do: Enum.each(waiters, &GenServer.reply(&1, result))

  defp succeed(state, status, binding) do
    result = if status == :unknown and state.initial != nil, do: {:ok, :unknown}, else: :ok
    reply_waiters(state.waiters, result)
    %{state | binding: binding, result: result, status: status, waiters: []}
  end

  defp fail(state, reason, usage_outcome) do
    result = {:error, reason}
    :ok = MediaAdmission.revoke(state.media_admission, self())
    reply_waiters(state.waiters, result)
    Process.send_after(self(), :retire, 1_000)
    state = finish_usage(state, usage_outcome)
    %{state | result: result, status: :failed, waiters: []}
  end

  defp adopt_submission(state, submission) do
    with {:ok, binding} <-
           OutgoingLegIdentity.from_submission(
             submission,
             state.leg_id,
             state.request,
             state.service,
             self()
           ),
         :ok <- register_and_bind(state, binding) do
      {:ok, binding}
    end
  end

  defp register_and_bind(state, %MediaBinding{} = binding) do
    key = IngressIdentity.leg_key(state.service.identity, binding.provider_call_leg_id)

    case Registry.register(Vxpipe.Gateway.Telephony.LegRegistry, key, {:outgoing, state.service}) do
      {:ok, _owner} ->
        case Vxpipe.Gateway.Telephony.IngressRegistration.register(
               state.service,
               binding.provider_call_leg_id,
               :outgoing
             ) do
          {:ok, ingress_keys} ->
            bind_registered(state, [key | ingress_keys], binding)

          {:error, _reason} ->
            Registry.unregister(Vxpipe.Gateway.Telephony.LegRegistry, key)
            {:error, :telephony_leg_already_owned}
        end

      {:error, {:already_registered, _owner}} ->
        {:error, :telephony_leg_already_owned}
    end
  end

  defp handle_adopted_event(%Event{} = event, binding, state) do
    state = state |> Map.merge(%{binding: binding, status: :accepted}) |> observe_usage(event)

    case InitialLegLifecycle.adopted(state, event) do
      {:stop, state} -> {:stop, :normal, :ok, finish_stopped_usage(state, event)}
      {:keep, state} -> handle_active_adopted_event(event, binding, state)
    end
  end

  defp handle_active_adopted_event(%Event{kind: :outgoing}, _binding, state),
    do: {:reply, :ok, state}

  defp handle_active_adopted_event(event, binding, state) do
    state = InitialLegLifecycle.observe(state, event)

    case OutgoingLegLifecycle.handle(event, binding, state.service, state.leg_id) do
      {:keep, result} -> {:reply, result, state}
      {:stop, result} -> {:stop, :normal, result, finish_stopped_usage(state, event)}
    end
  end

  defp report_media_ready(%{purpose: :initial}, _connection_id, _source), do: :ok

  defp report_media_ready(_transfer, connection_id, source),
    do: MediaSupervisor.report_transfer_control(connection_id, source, :media_ready)

  defp start_media(state, source, stream_id) do
    with {:ok, _connection} <-
           MediaSupervisor.start_outbound_session(
             state.media_supervisor,
             state.request,
             state.binding,
             source,
             stream_id
           ),
         :ok <- report_media_ready(state.request, state.binding.client_state_leg_id, source),
         do: :ok
  end

  defp release_pending_media(%{pending_media: {source, stream_id}} = state) do
    if InitialLegLifecycle.hold_media?(state) do
      {:ok, state}
    else
      {start_media(state, source, stream_id), %{state | pending_media: nil}}
    end
  end

  defp release_pending_media(state), do: {:ok, state}

  defp bind_registered(state, keys, binding) do
    case MediaAdmission.bind(state.media_admission, binding) do
      :ok ->
        :ok

      {:error, reason} ->
        Enum.each(keys, &Registry.unregister(Vxpipe.Gateway.Telephony.LegRegistry, &1))
        {:error, reason}
    end
  end

  defp observe_usage(state, event) do
    %{state | usage: LegUsage.observe(state.usage, event)}
  end

  defp finish_stopped_usage(state, %Event{kind: :ended}), do: state
  defp finish_stopped_usage(state, %Event{}), do: finish_usage(state, :cancelled)

  defp finish_usage(state, outcome) do
    %{state | usage: LegUsage.fail(state.usage, outcome)}
  end

  defp via(leg_id, service) do
    {:via, Registry,
     {Vxpipe.Gateway.Telephony.LegRegistry, {:outgoing, leg_id}, {:outgoing, service}}}
  end
end
