defmodule Vxpipe.CallEngine.RoomAuthority.OutgoingCall do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomDialSupervisor
  alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, OutgoingAdmission, StartupReadiness}
  alias Vxpipe.CallEngine.RoomAuthority.OutgoingCallFacts
  alias Vxpipe.CallEngine.Telephony.{OutboundLegConnector, OutboundLegRequestResolver}

  def start(%{participant_transfer_runtime: %{plan: %{direction: :outgoing}}} = state) do
    runtime = state.participant_transfer_runtime
    plan = runtime.plan
    callee = Map.fetch!(plan.participants, plan.entry_caller)

    with {:ok, request} <-
           OutboundLegRequestResolver.resolve(plan, callee, state.snapshot.incarnation_id) do
      timer = Keyword.fetch!(runtime.startup_options, :outgoing_timer)
      clock = Keyword.fetch!(runtime.startup_options, :outgoing_clock)
      {timer_module, timer_options} = timer
      deadline = clock.() + plan.ring_timeout_ms

      handle =
        timer_module.schedule(
          self(),
          request.attempt_id,
          :outgoing_ring,
          plan.ring_timeout_ms,
          timer_options
        )

      connector = Keyword.get(runtime.startup_options, :outbound_leg_connector)
      state = OutgoingCallFacts.emit(state, :outgoing_dial_submitted)

      task =
        RoomDialSupervisor.submit(state.snapshot.incarnation_id, fn ->
          {:outgoing_submitted,
           OutboundLegConnector.connect(
             connector,
             request,
             max(deadline - clock.(), 0)
           )}
        end)

      {:ok,
       %{
         state
         | outgoing_call: %{
             attempt_id: request.attempt_id,
             participant_id: callee.participant_id,
             task: task,
             handle: nil,
             monitor: nil,
             timer: timer,
             timer_handle: handle,
             outcome: nil,
             submitted?: false,
             answered?: false,
             deadline_ms: deadline,
             clock: clock
           }
       }}
    end
  end

  def start(state), do: {:ok, state}

  def submitted(
        reference,
        result,
        %{outgoing_call: %{task: %Task{ref: reference}} = outgoing} = state
      ) do
    Process.demonitor(reference, [:flush])
    state = %{state | outgoing_call: %{outgoing | task: nil}}

    case result do
      {:ok, handle} ->
        state = OutgoingAdmission.acknowledge(state, {:ok, handle.submission_status})

        outgoing = %{
          state.outgoing_call
          | handle: handle,
            monitor: Process.monitor(handle.owner),
            submitted?: true
        }

        state = %{state | outgoing_call: outgoing}

        cond do
          expired?(outgoing) ->
            finish(:no_answer, state)

          handle.submission_status == :unknown ->
            finish(:unknown, state)

          true ->
            state = if callee_connected?(state), do: answered(state), else: state
            StartupReadiness.reply(StartupReadiness.ready(state), state)
        end

      {:error, _reason} ->
        state = OutgoingAdmission.acknowledge(state, {:error, :dial_submission_failed})
        finish(:failed, state)
    end
  end

  def submitted(_reference, _result, state), do: {:noreply, state}

  def report(token, owner, :connected, %{outgoing_call: %{attempt_id: token}} = state)
      when is_pid(owner) do
    if current_owner?(state.outgoing_call, owner) do
      state = OutgoingAdmission.acknowledge(state, {:ok, :accepted})

      if expired?(state.outgoing_call) do
        finish(:no_answer, state)
      else
        outgoing = cancel_timer(state.outgoing_call)
        {:noreply, %{state | outgoing_call: %{outgoing | answered?: true}}}
      end
    else
      {:noreply, state}
    end
  end

  def report(token, owner, :answered, %{outgoing_call: %{attempt_id: token}} = state)
      when is_pid(owner) do
    cond do
      not current_owner?(state.outgoing_call, owner) ->
        {:noreply, state}

      expired?(state.outgoing_call) ->
        finish(:no_answer, OutgoingAdmission.acknowledge(state, {:ok, :accepted}))

      true ->
        state = OutgoingAdmission.acknowledge(state, {:ok, :accepted})
        state = answered(state)
        StartupReadiness.reply(StartupReadiness.ready(state), state)
    end
  end

  def report(token, owner, {:ended, reason}, %{outgoing_call: %{attempt_id: token}} = state)
      when is_pid(owner) and reason in [:hangup, :busy, :no_answer, :failed, :timeout, :machine] do
    if current_owner?(state.outgoing_call, owner) do
      state = OutgoingAdmission.acknowledge(state, {:ok, :accepted})

      outcome =
        if expired?(state.outgoing_call),
          do: :no_answer,
          else: state.outgoing_call.outcome || normalize(reason)

      finish(outcome, state)
    else
      {:noreply, state}
    end
  end

  def report(_token, _owner, _event, state), do: {:noreply, state}

  def timeout(token, %{outgoing_call: %{attempt_id: token, answered?: false}} = state),
    do: finish(:no_answer, state)

  def timeout(_token, state), do: {:noreply, state}

  def connection_attached(
        command,
        %{outgoing_call: %{participant_id: id, answered?: false}} = state
      )
      when command.participant_id == id do
    if expired?(state.outgoing_call), do: state, else: answered(state)
  end

  def connection_attached(_command, state), do: state

  def media_ready?(%{outgoing_call: nil}), do: true

  def media_ready?(state) do
    state.outgoing_call.submitted? and state.outgoing_call.outcome == :answered and
      callee_connected?(state)
  end

  defp callee_connected?(state) do
    Enum.any?(state.connections, fn {_id, connection} ->
      connection.participant_id == state.outgoing_call.participant_id and
        connection.admission == :main
    end)
  end

  defp expired?(outgoing),
    do: not outgoing.answered? and outgoing.clock.() >= outgoing.deadline_ms

  def owner_down(monitor, _reason, %{outgoing_call: %{monitor: monitor}} = state)
      when is_reference(monitor), do: finish(state.outgoing_call.outcome || :failed, state)

  def owner_down(monitor, _reason, %{outgoing_call: %{task: %Task{ref: monitor}}} = state),
    do: finish(:failed, state)

  def owner_down(_monitor, _reason, state), do: {:noreply, state}

  defp finish(outcome, state) do
    state = OutgoingCallFacts.emit(state, :outgoing_dial_ended, outcome)
    outgoing = cancel_timer(state.outgoing_call)
    if outgoing.handle, do: OutboundLegConnector.disconnect(outgoing.handle)
    ConnectionLifecycle.notify(state.connections, :call_ended)

    {:stop, {:shutdown, {:outgoing_call, outcome}},
     %{state | outgoing_call: %{outgoing | outcome: outcome}}}
  end

  defp answered(state) do
    state =
      if state.outgoing_call.outcome == nil,
        do: OutgoingCallFacts.emit(state, :outgoing_call_answered, :answered),
        else: state

    outgoing = cancel_timer(state.outgoing_call)
    %{state | outgoing_call: %{outgoing | answered?: true, outcome: :answered}}
  end

  defp cancel_timer(%{timer_handle: nil} = outgoing), do: outgoing

  defp cancel_timer(outgoing) do
    {module, options} = outgoing.timer
    module.cancel(outgoing.timer_handle, options)
    %{outgoing | timer_handle: nil}
  end

  defp current_owner?(%{handle: nil}, _owner), do: true
  defp current_owner?(%{handle: handle}, owner), do: handle.owner == owner
  defp normalize(:hangup), do: :rejected
  defp normalize(:timeout), do: :no_answer
  defp normalize(reason), do: reason
end
