defmodule Vxpipe.Gateway.Telephony.CallerRecoveryPeer do
  @moduledoc "Owns the linked carrier leg, its commands, and its cleanup membership."
  use GenServer, restart: :temporary

  alias Vxpipe.CallEngine.Telephony.{EndLeg, Event, LegReference, OutboundLegRequest, Submission}

  alias Vxpipe.Gateway.Telephony.{
    CarrierCleanup,
    EndCommandRetry,
    IncomingSubmission,
    IngressRegistration,
    LegSupervisor,
    LegUsage
  }

  alias Vxpipe.Gateway.Telephony.ProviderEndpoint

  @registry Vxpipe.Gateway.Telephony.LegRegistry

  def prepare(state, participant) do
    binding = state.incoming_identity.binding
    call = state.claim.call

    request = %OutboundLegRequest{
      tenant_id: call.tenant_key,
      actor_id: call.plan.actor_id,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: participant.participant_id,
      service_id: participant.connection.service,
      service_reference: participant.telephony_service,
      to: participant.connection.number
    }

    id = "peer-" <> binding.client_state_leg_id

    args = %{
      id: id,
      parent: self(),
      request: request,
      service: state.service,
      caller: binding,
      cleanup: state.cleanup
    }

    DynamicSupervisor.start_child(LegSupervisor, {__MODULE__, args})
  end

  def start_link(args) do
    name = {:via, Registry, {@registry, {:outgoing, args.id}, {:recovery_peer, args.service}}}
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def dial(peer), do: GenServer.cast(peer, :dial)
  def abandon(peer), do: GenServer.cast(peer, :abandon)

  @impl true
  def init(args) do
    with {:ok, cleanup} <- attach(args) do
      usage = LegUsage.start_outgoing(args.request, args.service, args.id, [])

      {:ok,
       Map.merge(args, %{
         parent_ref: Process.monitor(args.parent),
         usage: usage,
         cleanup: cleanup,
         phase: :prepared,
         control: nil,
         carrier_leg: nil,
         terminal: nil,
         ending?: false,
         workers: %{},
         drained?: true,
         end_accepted?: false,
         end_retry: %EndCommandRetry{}
       })}
    end
  end

  defp attach(%{cleanup: nil}), do: {:ok, nil}

  defp attach(%{cleanup: source, caller: caller}) do
    case CarrierCleanup.attach(caller.cleanup_binding, :outgoing_leg, source.binding,
           calls_options: source.calls_options
         ) do
      {:ok, cleanup} -> {:ok, cleanup}
      _unavailable -> {:stop, :cleanup_unavailable}
    end
  end

  @impl true
  def handle_cast(:dial, %{phase: :prepared, ending?: false} = state) do
    command = %{
      id: state.id,
      from: state.service.outbound_number,
      to: state.request.to,
      caller: state.caller.provider_call_control_id,
      callback_url: ProviderEndpoint.event_url(state.service, state.id),
      timeout_secs: 20
    }

    state = %{state | phase: :submitted}

    case submit(state, :dial, fn ->
           state.service.adapter.dial_recovery_peer(state.service.adapter_options, command)
         end) do
      {:ok, state} -> {:noreply, state}
      :error -> finish(rejected(state))
    end
  end

  def handle_cast(:dial, state), do: {:noreply, state}
  def handle_cast(:abandon, state), do: finish(abandon_leg(state))

  @impl true
  def handle_call({:event, %Event{} = event}, _from, state) do
    case accept_event(state, event) do
      {:ok, state} ->
        send(self(), :settle)
        {:reply, :ok, state}

      :mismatch ->
        {:reply, {:error, :telephony_leg_mismatch}, state}
    end
  end

  @impl true
  def handle_info({:incoming_submission, kind, pid, result}, state) do
    case state.workers[kind] do
      {^pid, _} -> finish(result(state, kind, result))
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, parent, _}, %{parent_ref: ref, parent: parent} = state),
    do: finish(abandon_leg(state))

  def handle_info({:retry_carrier_end, token}, state) do
    case EndCommandRetry.take(state.end_retry, token) do
      {:ok, retry} -> finish(end_leg(%{state | end_retry: retry}))
      :stale -> {:noreply, state}
    end
  end

  def handle_info(:settle, state), do: finish(state)

  def handle_info(msg, state) do
    case worker_down(msg, state.workers) do
      {kind, reason} ->
        state = %{
          state
          | workers: Map.delete(state.workers, kind),
            drained?: state.drained? and reason == :normal
        }

        state =
          if kind == :end and state.ending? and !state.terminal and !state.end_accepted?,
            do: %{state | end_retry: EndCommandRetry.schedule(state.end_retry)},
            else: state

        finish(state)

      nil ->
        case state.cleanup && CarrierCleanup.handle_info(state.cleanup, msg) do
          {:handled, cleanup} -> finish(%{state | cleanup: cleanup})
          _ -> {:noreply, state}
        end
    end
  end

  defp worker_down({:DOWN, ref, :process, pid, reason}, workers),
    do: Enum.find_value(workers, fn {kind, pair} -> if pair == {pid, ref}, do: {kind, reason} end)

  defp worker_down(_msg, _workers), do: nil

  defp submit(state, kind, effect) do
    case IncomingSubmission.start(self(), kind, effect) do
      {:ok, pid, ref} -> {:ok, %{state | workers: Map.put(state.workers, kind, {pid, ref})}}
      _ -> :error
    end
  end

  defp result(%{terminal: terminal} = state, _, _) when not is_nil(terminal), do: state

  defp result(state, :end, result),
    do: %{state | end_accepted?: EndCommandRetry.accepted?(result)}

  defp result(state, :dial, {:ok, %Submission{status: :accepted} = sub}) do
    case identify(
           state,
           sub.provider_call_control_id,
           sub.provider_call_leg_id,
           sub.provider_call_session_id
         ) do
      {:ok, state} -> maybe_end(%{state | usage: LegUsage.identify(state.usage, sub)})
      :mismatch -> state
    end
  end

  defp result(%{control: nil} = state, :dial, {:error, {:telnyx_command_rejected, _}}),
    do: rejected(state)

  defp result(state, :dial, _ambiguous), do: state

  defp rejected(state) do
    send(state.parent, {:recovery_peer, self(), :failed})
    %{state | terminal: :not_submitted, usage: LegUsage.fail(state.usage, :failed)}
  end

  defp accept_event(%{phase: :prepared}, _), do: :mismatch

  defp accept_event(state, event) do
    with true <- event.provider_connection_id == state.caller.provider_connection_id,
         true <-
           event.kind != :outgoing or (event.leg_id == state.id and event.to == state.request.to),
         {:ok, state} <-
           identify(
             state,
             event.provider_call_control_id,
             event.provider_call_leg_id,
             event.provider_call_session_id
           ) do
      {:ok, apply_event(state, event)}
    else
      _ -> :mismatch
    end
  end

  defp identify(state, control, leg, session) do
    cond do
      session != state.caller.provider_call_session_id or not is_binary(control) or
        not is_binary(leg) or
        control == state.caller.provider_call_control_id or
          leg == state.caller.provider_call_leg_id ->
        :mismatch

      state.control == control and state.carrier_leg == leg ->
        {:ok, state}

      state.control != nil ->
        :mismatch

      true ->
        case IngressRegistration.register(state.service, leg, :recovery_peer) do
          {:ok, _} -> {:ok, %{state | control: control, carrier_leg: leg}}
          _ -> :mismatch
        end
    end
  end

  defp apply_event(%{terminal: terminal} = state, _) when not is_nil(terminal), do: state

  defp apply_event(state, %Event{kind: :ended} = event) do
    outcome = if event.callee_declined?, do: :rejected, else: event.end_reason
    send(state.parent, {:recovery_peer, self(), {:ended, outcome}})

    %{
      state
      | terminal: :carrier_ended,
        usage: LegUsage.observe(state.usage, event),
        end_retry: EndCommandRetry.cancel(state.end_retry)
    }
  end

  defp apply_event(%{ending?: false} = state, %Event{kind: :bridged} = event) do
    send(state.parent, {:recovery_peer, self(), :bridged})
    %{state | phase: :bridged, usage: LegUsage.observe(state.usage, event)}
  end

  defp apply_event(state, event),
    do: maybe_end(%{state | usage: LegUsage.observe(state.usage, event)})

  defp abandon_leg(%{phase: :prepared} = state),
    do: %{
      state
      | ending?: true,
        terminal: :not_submitted,
        usage: LegUsage.fail(state.usage, :cancelled)
    }

  defp abandon_leg(state), do: end_leg(%{state | ending?: true})
  defp maybe_end(%{ending?: true} = state), do: end_leg(state)
  defp maybe_end(state), do: state

  defp end_leg(%{terminal: terminal} = state) when not is_nil(terminal), do: state
  defp end_leg(%{control: nil} = state), do: state
  defp end_leg(%{end_accepted?: true} = state), do: state
  defp end_leg(%{workers: %{end: _}} = state), do: state

  defp end_leg(state) do
    request = %EndLeg{
      leg: %LegReference{leg_id: state.id, provider_call_control_id: state.control},
      reason: :transfer_failed
    }

    case submit(state, :end, fn ->
           state.service.adapter.end_leg(state.service.adapter_options, request)
         end) do
      {:ok, state} -> state
      :error -> %{state | end_retry: EndCommandRetry.schedule(state.end_retry)}
    end
  end

  defp finish(%{terminal: nil} = state), do: {:noreply, state}

  defp finish(%{cleanup: nil} = state) do
    if commands_drained?(state), do: {:stop, :normal, state}, else: {:noreply, state}
  end

  defp finish(state) do
    with {:ok, cleanup} <- CarrierCleanup.begin_final(state.cleanup, state.usage),
         {:ok, cleanup} <-
           CarrierCleanup.acknowledge(
             cleanup,
             state.usage,
             state.terminal,
             commands_drained?(state)
           ) do
      {:stop, :normal, %{state | cleanup: cleanup}}
    else
      {:error, _, cleanup} -> {:noreply, %{state | cleanup: cleanup}}
    end
  end

  defp commands_drained?(state), do: state.drained? and map_size(state.workers) == 0
end
