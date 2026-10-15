defmodule Vxpipe.Gateway.Telephony.OutgoingLeg do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Telephony.{Event, Submission}

  alias Vxpipe.Gateway.Telephony.{
    DialSupervisor,
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
       dial_worker: nil,
       dial_result_received?: false,
       commands_drained?: true,
       retire?: false,
       retire_unknown?: false,
       carrier_control_id: nil,
       cancel_reason: nil,
       end_requested?: false,
       end_retry?: false,
       end_worker: nil,
       early_events: [],
       service: Keyword.fetch!(options, :service),
       deadline_ms: Keyword.get(options, :deadline_ms),
       monotonic_clock: Keyword.fetch!(options, :monotonic_clock),
       media_admission: Keyword.fetch!(options, :media_admission),
       media_reserved?: false,
       cleanup_scope: Keyword.get(options, :cleanup_scope),
       cleanup_options: Keyword.get(options, :cleanup_options, []),
       cleanup_binding: nil,
       cleanup: nil,
       cleanup_room_monitor: nil,
       cleanup_room_closed?: false,
       dial_dispatched?: false,
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
    with {:ok, binding} <- OutgoingLegLifecycle.validate_cleanup(state),
         {:ok, usage} <-
           OutgoingLegDialer.identify(
             state.leg_id,
             state.request,
             state.service,
             state.usage_options
           ) do
      state = %{state | usage: usage, cleanup_binding: binding}

      case OutgoingLegLifecycle.attach_cleanup(state) do
        {:ok, state} ->
          if is_integer(state.deadline_ms) and state.monotonic_clock.() >= state.deadline_ms,
            do: continue(fail(state, :outbound_connection_unavailable, :failed)),
            else: submit_dial(state)

        {:error, reason, state} ->
          continue(fail(state, reason, :failed))
      end
    else
      {:error, reason} -> continue(fail(state, reason, :failed))
    end
  end

  defp submit_dial(state) do
    case OutgoingLegDialer.prepare(
           state.leg_id,
           state.request,
           state.service,
           state.media_admission,
           self(),
           state.usage
         ) do
      {:ok, dial, usage} ->
        state = %{state | usage: usage, media_reserved?: true}

        case DialSupervisor.submit(self(), state.service, dial) do
          {:ok, worker, monitor} ->
            {:noreply, %{state | dial_worker: {worker, monitor}, dial_dispatched?: true}}

          {:error, _reason} ->
            {:noreply, fail(state, :dial_submission_unavailable, :failed)}
        end

      {:error, reason, usage} ->
        {:noreply, state |> Map.put(:usage, usage) |> fail(reason, :failed)}
    end
  end

  defp submitted(_result, %{status: :ended} = state), do: continue(state)

  # An authenticated callback is acceptance evidence even if the REST result is lost.
  defp submitted(_result, %{status: :accepted} = state), do: continue(state)

  defp submitted({:ok, %Submission{status: :accepted} = submission}, state) do
    state = identify_submission(state, submission)

    case adopt_submission(state, submission) do
      {:ok, binding} ->
        state
        |> succeed(:accepted, binding)
        |> OutgoingLegLifecycle.adopted()
        |> replay_early_events()

      {:error, _reason} ->
        state |> succeed(:unknown, nil) |> OutgoingLegLifecycle.adopted() |> continue()
    end
  end

  defp submitted({:ok, %Submission{status: :unknown} = submission}, state) do
    state
    |> identify_submission(submission)
    |> succeed(:unknown, nil)
    |> OutgoingLegLifecycle.adopted()
    |> continue()
  end

  defp submitted({:error, _reason}, %{cleanup: cleanup, dial_dispatched?: true} = state)
       when not is_nil(cleanup),
       do: state |> succeed(:unknown, nil) |> OutgoingLegLifecycle.adopted() |> continue()

  defp submitted({:error, reason}, state), do: {:noreply, fail(state, reason, :failed)}

  defp identify_submission(state, submission) do
    %{
      state
      | usage: LegUsage.identify(state.usage, submission),
        carrier_control_id: state.carrier_control_id || submission.provider_call_control_id
    }
  end

  defp replay_early_events(state) do
    initial = {:noreply, %{state | early_events: []}}
    Enum.reduce_while(state.early_events, initial, &replay_early_event/2)
  end

  defp replay_early_event(event, {:noreply, state}) do
    case handle_call({:event, event}, nil, state) do
      {:reply, _result, state} -> {:cont, {:noreply, state}}
      {:stop, reason, _result, state} -> {:halt, {:stop, reason, state}}
    end
  end

  @impl true
  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call(:disconnect, _from, state) do
    {:reply, :ok,
     OutgoingLegLifecycle.cancel(state, InitialLegLifecycle.cancellation_reason(state))}
  end

  def handle_call(
        {:event, %Event{kind: kind} = event},
        _from,
        %{binding: %MediaBinding{} = binding, cancel_reason: reason} = state
      )
      when not is_nil(reason) and kind in [:media_started, :media, :dtmf] do
    if MediaBinding.matches_event?(binding, event) do
      state =
        if kind == :media_started,
          do: state |> observe_usage(event) |> OutgoingLegLifecycle.late_answer(),
          else: state

      {:reply, :ok, state}
    else
      {:reply, {:error, :telephony_leg_mismatch}, state}
    end
  end

  def handle_call({:event, %Event{kind: kind} = event}, _from, %{status: :starting} = state)
      when kind in [:outgoing, :answered, :answering_machine, :ended] do
    case identity_from_event(state, event) do
      {:ok, binding} ->
        case register_and_bind(state, binding) do
          :ok -> handle_adopted_event(event, binding, succeed(state, :accepted, binding))
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, :telephony_leg_mismatch} ->
        buffer_early_event(state, event)
    end
  end

  def handle_call(
        {:event, %Event{kind: kind} = event},
        _from,
        %{status: :unknown} = state
      )
      when kind in [:outgoing, :answered, :ended] do
    case identity_from_event(state, event) do
      {:ok, binding} ->
        case register_and_bind(state, binding) do
          :ok -> handle_adopted_event(event, binding, state)
          {:error, reason} -> {:reply, {:error, reason}, state}
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
    case identity_from_event(state, event) do
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
    handle_lifecycle_event(event, binding, state)
  end

  def handle_call({:event, _event}, _from, state) do
    {:reply, {:error, :telephony_event_not_supported}, state}
  end

  defp buffer_early_event(state, event) do
    cond do
      not OutgoingLegIdentity.pending_event?(event, state.leg_id, state.request, state.service) ->
        {:reply, {:error, :telephony_leg_mismatch}, state}

      event in state.early_events ->
        {:reply, :ok, state}

      length(state.early_events) >= 32 ->
        {:reply, {:error, :telephony_event_buffer_full}, state}

      true ->
        {:reply, :ok, %{state | early_events: state.early_events ++ [event]}}
    end
  end

  @impl true
  def handle_cast(:abandon, state) do
    {:noreply, OutgoingLegLifecycle.cancel(state, InitialLegLifecycle.cancellation_reason(state))}
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{cleanup_room_monitor: monitor} = state
      )
      when is_reference(monitor) do
    state = %{state | cleanup_room_closed?: true}

    state
    |> OutgoingLegLifecycle.cancel(InitialLegLifecycle.cancellation_reason(state))
    |> continue()
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{initial: %{room_monitor: monitor}} = state
      ) do
    {:noreply, OutgoingLegLifecycle.cancel(state, InitialLegLifecycle.cancellation_reason(state))}
  end

  def handle_info({:outgoing_dial_result, worker, result}, %{dial_worker: {worker, _}} = state) do
    submitted(result, %{state | dial_result_received?: true})
  end

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{dial_worker: {worker, monitor}} = state
      ) do
    state = %{
      state
      | dial_worker: nil,
        commands_drained?: state.commands_drained? and reason == :normal
    }

    if state.dial_result_received?,
      do: continue(state),
      else: submitted({:ok, %Submission{status: :unknown, provider_call_control_id: nil}}, state)
  end

  def handle_info({:outgoing_end_result, worker, _result}, %{end_worker: {worker, _}} = state),
    do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{end_worker: {worker, monitor}} = state
      ) do
    state = %{state | commands_drained?: state.commands_drained? and reason == :normal}
    state |> OutgoingLegLifecycle.end_worker_down() |> continue()
  end

  def handle_info(:retire_unknown, state), do: continue(%{state | retire_unknown?: true})
  def handle_info(:retire, state), do: continue(%{state | retire?: true})

  def handle_info(message, state) do
    case OutgoingLegLifecycle.cleanup_message(state, message) do
      {:handled, state} -> continue(state)
      :unhandled -> {:noreply, state}
    end
  end

  defp continue(%{cleanup: cleanup} = state) when not is_nil(cleanup),
    do: OutgoingLegLifecycle.continue_cleanup(state)

  # An abnormal observer exit cannot attest that its separate HTTP task has drained.
  defp continue(%{commands_drained?: false} = state), do: {:noreply, state}

  defp continue(%{dial_worker: nil, end_worker: nil} = state) do
    cond do
      state.status == :ended or (state.status == :failed and state.retire?) ->
        {:stop, :normal, state}

      state.retire_unknown? and not is_nil(state.cancel_reason) and
          is_nil(state.carrier_control_id) ->
        {:stop, :normal, finish_usage(state, :unknown)}

      true ->
        {:noreply, state}
    end
  end

  defp continue(state), do: {:noreply, state}

  defp reply(result, state) do
    case continue(state) do
      {:stop, reason, state} -> {:stop, reason, result, state}
      {:noreply, state} -> {:reply, result, state}
    end
  end

  defp reply_waiters(waiters, result), do: Enum.each(waiters, &GenServer.reply(&1, result))

  defp succeed(state, status, binding) do
    result = if status == :unknown, do: {:ok, :unknown}, else: :ok
    reply_waiters(state.waiters, result)
    %{state | binding: binding, result: result, status: status, waiters: []}
  end

  defp fail(state, reason, usage_outcome) do
    result = {:error, reason}
    if state.media_reserved?, do: MediaAdmission.revoke(state.media_admission, self())
    reply_waiters(state.waiters, result)
    if is_nil(state.cleanup), do: Process.send_after(self(), :retire, 1_000)
    state = finish_usage(state, usage_outcome)

    %{state | result: result, status: :failed, waiters: []}
    |> OutgoingLegLifecycle.store_final()
  end

  defp adopt_submission(%{binding: %MediaBinding{} = binding} = state, submission) do
    case identity_from_submission(state, submission) do
      {:ok, ^binding} -> {:ok, binding}
      _mismatch -> {:error, :telephony_leg_mismatch}
    end
  end

  defp adopt_submission(state, submission) do
    with {:ok, binding} <-
           identity_from_submission(state, submission),
         :ok <- register_and_bind(state, binding) do
      {:ok, binding}
    end
  end

  defp register_and_bind(%{carrier_control_id: known}, %MediaBinding{
         provider_call_control_id: received
       })
       when not is_nil(known) and known != received,
       do: {:error, :telephony_leg_mismatch}

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
    state = %{
      state
      | binding: binding,
        status: :accepted,
        carrier_control_id: binding.provider_call_control_id
    }

    state = if event.kind == :ended, do: state, else: OutgoingLegLifecycle.adopted(state)

    case handle_lifecycle_event(event, binding, state) do
      {:reply, result, state} ->
        case replay_early_events(state) do
          {:noreply, state} -> {:reply, result, state}
          {:stop, reason, state} -> {:stop, reason, result, state}
        end

      stopped ->
        stopped
    end
  end

  defp handle_lifecycle_event(event, binding, state) do
    case OutgoingLegLifecycle.handle(event, binding, state.service, state.leg_id) do
      {:keep, {:error, _} = result} ->
        {:reply, result, state}

      {:stop, result} ->
        MediaAdmission.revoke(state.media_admission, self())
        state = state |> observe_usage(event) |> InitialLegLifecycle.observe(event)
        reply(result, %{state | status: :ended, pending_media: nil})

      {:cancel, reason} ->
        state =
          state
          |> observe_usage(event)
          |> InitialLegLifecycle.observe(event)
          |> OutgoingLegLifecycle.cancel(reason)

        {:reply, :ok, state}

      {:keep, result} ->
        state = observe_usage(state, event)

        if state.cancel_reason do
          state =
            if event.kind == :answered, do: OutgoingLegLifecycle.late_answer(state), else: state

          {:reply, result, state}
        else
          state = InitialLegLifecycle.observe(state, event)
          {media_result, state} = release_pending_media(state)
          {:reply, if(result == :ok, do: media_result, else: result), state}
        end
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

  defp bind_registered(%{cancel_reason: reason}, _keys, _binding) when not is_nil(reason), do: :ok

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

  defp finish_usage(state, outcome) do
    %{state | usage: LegUsage.fail(state.usage, outcome)}
  end

  defp identity_from_event(state, event) do
    case OutgoingLegIdentity.from_event(event, state.leg_id, state.request, state.service, self()) do
      {:ok, binding} -> {:ok, %{binding | cleanup_binding: state.cleanup_binding}}
      error -> error
    end
  end

  defp identity_from_submission(state, submission) do
    case OutgoingLegIdentity.from_submission(
           submission,
           state.leg_id,
           state.request,
           state.service,
           self()
         ) do
      {:ok, binding} -> {:ok, %{binding | cleanup_binding: state.cleanup_binding}}
      error -> error
    end
  end

  defp via(leg_id, service) do
    {:via, Registry,
     {Vxpipe.Gateway.Telephony.LegRegistry, {:outgoing, leg_id}, {:outgoing, service}}}
  end
end
