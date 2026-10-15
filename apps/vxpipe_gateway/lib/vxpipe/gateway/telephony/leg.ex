defmodule Vxpipe.Gateway.Telephony.Leg do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.Telephony.{Event, Submission}
  alias Vxpipe.Calls.TelephonyAdmissionClaim

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    IncomingLegActivationResult,
    IncomingLegActivationContext,
    IncomingLegIdentity,
    IncomingSubmission,
    MediaAdmission,
    IngressIdentity,
    IngressRegistration,
    LegUsage
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    service = Keyword.fetch!(options, :service)
    event = Keyword.fetch!(options, :event)
    GenServer.start_link(__MODULE__, options, name: via(service, event))
  end

  def child_spec(options) do
    service = Keyword.fetch!(options, :service)
    event = Keyword.fetch!(options, :event)

    %{
      id: {__MODULE__, key(service.identity, event)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec await(pid(), timeout()) :: :ok | {:ok, term()} | {:error, term()}
  def await(leg, timeout) when is_pid(leg) do
    GenServer.call(leg, :await, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  def await(leg, %ConfiguredService{} = service, %Event{} = event, timeout) do
    GenServer.call(leg, {:await_incoming, service, event}, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @spec dispatch(pid(), Event.t(), timeout()) :: :ok | {:error, term()}
  def dispatch(leg, %Event{} = event, timeout) when is_pid(leg) do
    GenServer.call(leg, {:event, event}, timeout)
  catch
    :exit, _reason -> {:error, :telephony_leg_unavailable}
  end

  @doc false
  def dispatch_async(leg, %Event{} = event) when is_pid(leg),
    do: :gen_server.send_request(leg, {:event, event})

  @impl true
  def init(options) do
    service = Keyword.fetch!(options, :service)
    event = Keyword.fetch!(options, :event)

    {:ok, _keys} = IngressRegistration.register(service, event.provider_call_leg_id, :incoming)

    state = %{
      activation: nil,
      incoming_identity: nil,
      prepared: nil,
      answer_worker: nil,
      answer_result_received?: false,
      commands_drained?: true,
      retire?: false,
      end_worker: nil,
      end_requested?: false,
      end_retry?: false,
      carrier_ended?: false,
      token: make_ref(),
      backend: Keyword.fetch!(options, :backend),
      claim: nil,
      clock: Keyword.fetch!(options, :clock),
      identity: service.identity,
      service: service,
      initial_event: Keyword.fetch!(options, :event),
      incarnation_id: nil,
      room_monitor: nil,
      room_closed?: false,
      result: nil,
      status: :starting,
      usage: nil,
      waiters: []
    }

    {:ok, state, {:continue, :admit}}
  end

  @impl true
  def handle_continue(:admit, state) do
    {:noreply, admit(state)}
  end

  @impl true
  def handle_call({:await_incoming, service, event}, from, state) do
    fields = [
      :provider,
      :provider_connection_id,
      :provider_call_control_id,
      :provider_call_leg_id,
      :provider_call_session_id
    ]

    if state.service == service and
         Map.take(event, fields) == Map.take(state.initial_event, fields) do
      handle_call(:await, from, state)
    else
      {:reply, {:error, :telephony_leg_mismatch}, state}
    end
  end

  def handle_call(:await, _from, %{result: result} = state) when not is_nil(result) do
    {:reply, result, state}
  end

  def handle_call(:await, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call(
        {:event, %Event{kind: kind} = event},
        {source, _tag},
        %{status: :answering} = state
      )
      when kind in [:answered, :media_started] do
    with :ok <- matching_event(state.claim, event) do
      state = observe_usage(state, event)

      case project_started(state, event) do
        {:ok, state} ->
          case dispatch_start_event(state, source, event) do
            :ok -> {:reply, :ok, state}
            {:error, reason} -> {:reply, {:error, reason}, state}
          end

        {:error, reason, state} ->
          {:reply, {:error, reason}, close(state, reason)}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, %Event{kind: kind} = event}, _from, %{status: :closing} = state)
      when kind in [:answered, :media_started] do
    case matching_event(state.claim, event) do
      :ok ->
        state =
          if state.carrier_ended?, do: state, else: state |> observe_usage(event) |> retry_end()

        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:event, %Event{kind: :answered} = event}, _from, %{status: :running} = state) do
    case matching_event(state.claim, event) do
      :ok -> {:reply, :ok, observe_usage(state, event)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, %Event{kind: :ended} = event}, {source, _tag}, state)
      when state.status in [:answering, :running, :closing, :failed] do
    with :ok <- matching_event(state.claim, event) do
      state = state |> observe_usage(event) |> revoke_media()

      result =
        if state.activation do
          call_backend(state.backend, :handle_live_event, [
            state.claim,
            state.activation,
            source,
            event
          ])
        else
          if state.incarnation_id && not state.room_closed? do
            call_backend(state.backend, :cancel_incoming, [
              state.claim,
              state.token,
              :carrier_ended
            ])
          else
            :ok
          end
        end

      status = if result == :ok, do: :ended, else: :closing
      state = reply_waiters(%{state | status: status, carrier_ended?: true}, :ok)
      if status == :ended and is_nil(state.room_monitor), do: send(self(), :retire)
      {:reply, result, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, %Event{kind: :ended} = event}, _from, %{status: :ended} = state) do
    {:reply, matching_event(state.claim, event), state}
  end

  def handle_call({:event, event}, {source, _tag}, %{status: :running} = state) do
    case matching_event(state.claim, event) do
      :ok ->
        state = observe_usage(state, event)

        case call_backend(state.backend, :handle_live_event, [
               state.claim,
               state.activation,
               source,
               event
             ]) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, _event}, _from, state) do
    {:reply, {:error, :telephony_leg_unavailable}, state}
  end

  @impl true
  def handle_info(:retire, state), do: maybe_retire(%{state | retire?: true})

  def handle_info(
        {:incoming_submission, :answer, worker, result},
        %{answer_worker: {worker, _monitor}} = state
      ) do
    state = answer_result(%{state | answer_result_received?: true}, result)
    maybe_retire(state)
  end

  def handle_info(
        {:incoming_submission, :end, worker, _result},
        %{end_worker: {worker, _monitor}} = state
      ),
      do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{answer_worker: {worker, monitor}} = state
      ) do
    state = %{
      state
      | answer_worker: nil,
        commands_drained?: state.commands_drained? and reason == :normal
    }

    state =
      if state.answer_result_received?,
        do: state,
        else: answer_result(state, {:error, :submission_unknown})

    maybe_retire(state)
  end

  def handle_info(
        {:DOWN, monitor, :process, worker, reason},
        %{end_worker: {worker, monitor}} = state
      ) do
    state = %{
      state
      | end_worker: nil,
        commands_drained?: state.commands_drained? and reason == :normal
    }

    state = if state.end_retry?, do: retry_end(%{state | end_retry?: false}), else: state
    maybe_retire(state)
  end

  def handle_info({:DOWN, monitor, :process, _room, _reason}, %{room_monitor: monitor} = state) do
    state = %{state | room_monitor: nil, room_closed?: true}

    state =
      if state.carrier_ended?,
        do: %{state | status: :ended, retire?: true},
        else: close(state, :room_ended)

    maybe_retire(state)
  end

  # A lost observer cannot attest that its separate HTTP operation has drained.
  defp maybe_retire(%{commands_drained?: false} = state), do: {:noreply, state}

  defp maybe_retire(%{retire?: true, answer_worker: nil, end_worker: nil, status: status} = state)
       when status in [:ended, :unclaimed, :replay],
       do: {:stop, :normal, state}

  defp maybe_retire(state), do: {:noreply, state}

  defp admit(state) do
    case call_backend(state.backend, :claim_incoming, [state.identity, state.initial_event]) do
      {:ok, %TelephonyAdmissionClaim{} = claim} ->
        start_call(%{state | claim: claim})

      {:duplicate, %TelephonyAdmissionClaim{} = claim} ->
        # A replay cannot establish ownership of a prior admission's effects.
        Process.send_after(self(), :retire, 1_000)
        reply_waiters(%{state | claim: claim, status: :replay}, :ok)

      {:error, reason} ->
        unclaimed(state, reason)

      _invalid ->
        unclaimed(state, :invalid_telephony_call_backend_response)
    end
  end

  defp unclaimed(state, reason) do
    Process.send_after(self(), :retire, 1_000)
    reply_waiters(%{state | status: :unclaimed}, {:error, reason})
  end

  defp start_call(state) do
    case call_backend(state.backend, :start_incoming, [
           state.claim,
           state.service,
           self(),
           state.token
         ]) do
      {:ok, %RoomSnapshot{} = room, monitor} ->
        # Retain exact room ownership before persistence or answer preparation.
        claim = %{state.claim | call: %{state.claim.call | incarnation_id: room.incarnation_id}}

        identify_call(
          %{state | claim: claim, incarnation_id: room.incarnation_id, room_monitor: monitor},
          room
        )

      {:error, _reason} ->
        _projection =
          call_backend(state.backend, :mark_incoming_failed, [state.claim, :room_start_failed])

        close(state, :room_start_failed)

      _invalid ->
        close(state, :invalid_telephony_call_backend_response)
    end
  end

  defp identify_call(state, room) do
    case call_backend(state.backend, :identify_incoming, [
           state.service,
           state.claim,
           room,
           self()
         ]) do
      {:ok, %IncomingLegIdentity{} = identity} ->
        bind_call(%{state | incoming_identity: identity, usage: identity.usage}, room)

      _failure ->
        close(state, :identity_preparation_failed)
    end
  end

  defp bind_call(state, room) do
    case call_backend(state.backend, :bind_incoming, [state.claim, room.incarnation_id]) do
      {:ok, :admit, %TelephonyAdmissionClaim{} = claim} ->
        prepare_call(%{state | claim: claim})

      {:ok, :cancel, %TelephonyAdmissionClaim{} = claim} ->
        close(%{state | claim: claim}, :admission_cancelled)

      _failure ->
        close(state, :admission_failed)
    end
  end

  defp prepare_call(state) do
    case call_backend(state.backend, :prepare_incoming, [state.incoming_identity]) do
      {:ok, prepared} ->
        activation = prepared_activation(prepared)

        state = %{
          state
          | prepared: prepared,
            activation: activation,
            status: :answering
        }

        case IncomingSubmission.start(self(), :answer, fn ->
               call_backend(state.backend, :submit_incoming, [prepared])
             end) do
          {:ok, worker, monitor} -> %{state | answer_worker: {worker, monitor}}
          _failure -> close(state, :answer_submission_failed)
        end

      _failure ->
        close(state, :answer_preparation_failed)
    end
  end

  defp prepared_activation(%IncomingLegActivationContext{} = prepared) do
    %IncomingLegActivationResult{
      binding: prepared.binding,
      media_url: prepared.media_url,
      service: prepared.service,
      usage: prepared.usage,
      submission: %Submission{
        status: :unknown,
        provider_call_control_id: prepared.binding.provider_call_control_id
      }
    }
  end

  defp prepared_activation(custom), do: custom

  defp answer_result(%{carrier_ended?: true} = state, _result),
    do: reply_waiters(state, :ok)

  defp answer_result(state, {:ok, activation}) do
    usage = identify_submission(state.usage, activation)
    state = %{state | usage: usage}

    if state.status in [:answering, :running] do
      reply_waiters(%{state | activation: activation}, activation_result(activation))
    else
      # An answer accepted after cancellation still belongs to this carrier leg.
      retry_end(reply_waiters(state, :ok))
    end
  end

  defp answer_result(%{status: :running} = state, _failure),
    do: reply_waiters(state, activation_result(state.activation))

  defp answer_result(%{status: :closing} = state, _failure),
    do: retry_end(reply_waiters(state, :ok))

  defp answer_result(state, _failure), do: close(state, :answer_submission_failed)

  defp identify_submission(usage, %IncomingLegActivationResult{submission: submission}),
    do: LegUsage.identify(usage, submission)

  defp identify_submission(usage, _custom), do: usage

  defp project_started(state, event) do
    with {:ok, claim} <-
           call_backend(state.backend, :mark_incoming_started, [
             state.claim,
             state.incarnation_id,
             start_time(event, state.clock)
           ]),
         :ok <- call_backend(state.backend, :release_incoming, [claim, state.token]) do
      {:ok, %{state | claim: claim, status: :running}}
    else
      {:error, reason} -> {:error, reason, state}
      _invalid -> {:error, :invalid_telephony_call_backend_response, state}
    end
  end

  defp retry_end(%{carrier_ended?: true} = state), do: state

  defp retry_end(%{end_worker: worker} = state) when not is_nil(worker),
    do: %{state | end_retry?: true}

  defp retry_end(state), do: close(%{state | end_requested?: false}, :admission_cancelled)

  defp close(%{status: :ended} = state, _reason), do: reply_waiters(state, :ok)

  defp close(state, reason) do
    state = revoke_media(state)

    if state.incarnation_id do
      _cancel = call_backend(state.backend, :cancel_incoming, [state.claim, state.token, reason])
    end

    state = %{state | status: :closing}

    state =
      if state.end_requested? or state.carrier_ended? do
        state
      else
        case IncomingSubmission.start(self(), :end, fn ->
               call_backend(state.backend, :end_incoming, [
                 state.service,
                 state.initial_event,
                 state.activation || state.incoming_identity,
                 reason
               ])
             end) do
          {:ok, worker, monitor} ->
            %{state | end_worker: {worker, monitor}, end_requested?: true}

          _failure ->
            state
        end
      end

    reply_waiters(state, :ok)
  end

  defp revoke_media(%{prepared: %IncomingLegActivationContext{} = prepared} = state) do
    MediaAdmission.revoke(prepared.media_admission, self())
    state
  end

  defp revoke_media(state), do: state

  defp reply_waiters(state, result) do
    Enum.each(state.waiters, &GenServer.reply(&1, result))
    %{state | result: result, waiters: []}
  end

  defp activation_result(%IncomingLegActivationResult{media_url: media_url}),
    do: {:ok, media_url}

  defp activation_result(_custom_activation), do: :ok

  defp observe_usage(state, event) do
    %{state | usage: LegUsage.observe(state.usage, event)}
  end

  defp start_time(%Event{occurred_at: %DateTime{} = occurred_at}, _clock), do: occurred_at
  defp start_time(%Event{kind: :media_started}, clock), do: clock.()

  defp dispatch_start_event(_state, _source, %Event{kind: :answered}), do: :ok

  defp dispatch_start_event(state, source, %Event{kind: :media_started} = event) do
    call_backend(state.backend, :handle_live_event, [state.claim, state.activation, source, event])
  end

  defp matching_event(claim, event) do
    if event.provider == claim.provider and
         event.provider_connection_id == claim.provider_connection_id and
         event.provider_call_control_id == claim.provider_call_control_id and
         event.provider_call_leg_id == claim.provider_call_leg_id and
         event.provider_call_session_id == claim.provider_call_session_id,
       do: :ok,
       else: {:error, :telephony_leg_mismatch}
  end

  defp call_backend({module, context}, function, arguments) do
    apply(module, function, [context | arguments])
  rescue
    _exception -> {:error, :telephony_call_backend_failed}
  catch
    _kind, _reason -> {:error, :telephony_call_backend_failed}
  end

  defp via(service, event) do
    {:via, Registry,
     {Vxpipe.Gateway.Telephony.LegRegistry, key(service.identity, event), {:incoming, service}}}
  end

  defp key(identity, event), do: IngressIdentity.leg_key(identity, event.provider_call_leg_id)
end
