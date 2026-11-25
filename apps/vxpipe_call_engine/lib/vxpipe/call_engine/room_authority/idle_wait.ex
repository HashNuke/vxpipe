defmodule Vxpipe.CallEngine.RoomAuthority.IdleWait do
  @moduledoc "Owns one scoped native idle operation and its playback-relative quiet timer."

  alias Vxpipe.CallEngine.{AgentActivationSupervisor, CallLifecycle, ResolvedCallPlan}
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator

  alias Vxpipe.CallEngine.RoomAuthority.{
    AgentOutput,
    IdleNotification,
    State,
    TextCapability,
    TurnState
  }

  alias Vxpipe.CallEngine.Tool.{Idle, InvocationBinding, InvocationRegistry}
  alias Vxpipe.CallEngine.Tool.Idle.Request

  @derive {Inspect, only: [:phase, :duration_ms]}
  @enforce_keys [
    :token,
    :context,
    :coordinator,
    :activation_id,
    :worker,
    :worker_monitor,
    :from,
    :duration_ms,
    :timer,
    :phase
  ]
  defstruct @enforce_keys ++ [timeout_command: nil]

  @type t :: %__MODULE__{}

  def begin(%Request{} = request, from, %State{idle_wait: nil} = state) do
    with {:ok, execution} <- authorize(request, state),
         arming_ms when arming_ms > 0 <- arming_budget(request, execution),
         {:ok, state} <- AgentOutput.interrupt_idle(request.context, state) do
      token = make_ref()
      timer = Process.send_after(self(), {:vxpipe_idle_wait_deadline, token, :armed}, arming_ms)

      wait = %__MODULE__{
        token: token,
        context: request.context,
        coordinator: execution.completion_target,
        activation_id: state.text_capability.activation_id,
        worker: execution.worker,
        worker_monitor: Process.monitor(execution.worker),
        from: from,
        duration_ms: request.duration_seconds * 1_000,
        timer: timer,
        phase: :armed
      }

      send(wait.coordinator, {:vxpipe_idle_armed, self(), token, request.context})
      {:noreply, reconcile(%{state | idle_wait: wait})}
    else
      _invalid_or_stale -> {:reply, {:error, :rejected}, state}
    end
  end

  def begin(%Request{}, _from, state), do: {:reply, {:error, :rejected}, state}

  def reconcile(%State{idle_wait: nil} = state), do: state

  def reconcile(%State{idle_wait: wait} = state) do
    cond do
      not current?(wait, state) ->
        cancel(state, :source_replaced)

      wait.phase == :armed and TurnState.get(state, wait.context) == nil ->
        start_quiet(state)

      wait.phase == :expiring and TurnState.get(state, wait.timeout_command) == nil ->
        finish(state)

      true ->
        state
    end
  end

  def cancel(%State{idle_wait: nil} = state, _reason), do: state

  def cancel(%State{idle_wait: wait} = state, reason) do
    send(wait.coordinator, {:vxpipe_idle_cancelled, self(), wait.token})
    reply_and_release(wait, {:ok, %{"status" => "cancelled", "reason" => Atom.to_string(reason)}})
    finish(%{state | idle_wait: nil})
  end

  def deadline(token, phase, %State{idle_wait: %{token: token, phase: phase}} = state) do
    if current?(state.idle_wait, state) do
      case phase do
        :armed -> cancel(state, :acknowledgment_timeout)
        :quiet -> expire(state)
      end
    else
      cancel(state, :source_replaced)
    end
  end

  def deadline(_token, _phase, state), do: state

  def worker_down(monitor, %State{idle_wait: %{worker_monitor: monitor}} = state)
      when is_reference(monitor),
      do: {:handled, cancel(state, :tool_unavailable)}

  def worker_down(_monitor, _state), do: :unhandled

  def acknowledgment_failed(
        capability,
        command,
        %State{idle_wait: %{phase: :armed} = wait} = state
      ) do
    if capability == wait.coordinator and TurnState.key(command) == TurnState.key(wait.context),
      do: cancel(state, :acknowledgment_failed),
      else: state
  end

  def acknowledgment_failed(_capability, _command, state), do: state

  def output_allowed?(%State{idle_wait: nil}, _capability, _command), do: true

  def output_allowed?(%State{idle_wait: wait}, capability, command) do
    expected = if wait.phase == :armed, do: wait.context, else: wait.timeout_command

    capability == wait.coordinator and expected != nil and
      TurnState.key(command) == TurnState.key(expected)
  end

  defp authorize(request, state) do
    context = request.context

    with %{module: Coordinator, activation_id: activation_id} when is_binary(activation_id) <-
           state.text_capability,
         true <-
           state.startup_ready? and
             MapSet.member?(state.participant_ids, context.source_participant_id) and
             not State.conversation_held?(state, context.source_participant_id),
         %{plan: plan} <- state.participant_transfer_runtime,
         %{"version" => "mode_message_v1"} <- ResolvedCallPlan.agent_protocol(plan),
         true <-
           context.tenant_id == state.snapshot.tenant_id and
             context.room_id == state.snapshot.room_id and
             context.incarnation_id == state.snapshot.incarnation_id and
             context.agent_participant_id == state.text_capability.participant_id,
         %{participant_id: participant_id} <- Map.get(state.connections, context.connection_id),
         true <- participant_id == context.source_participant_id,
         origin when not is_nil(origin) <- TurnState.get(state, context),
         {:ok, _targets} <- TurnState.idle_targets(state, context),
         registry = AgentActivationSupervisor.child_ref(activation_id, :invocation_registry),
         {:ok, execution} <- InvocationRegistry.running_execution(registry, context.tool_call_id),
         %InvocationBinding{handler: {:platform, Idle}, conversation_mode: :non_blocking} <-
           execution.binding,
         true <- execution.context == context,
         true <- execution.arguments == %{"duration_seconds" => request.duration_seconds},
         true <- TextCapability.current?(state, execution.completion_target) do
      {:ok, execution}
    else
      _invalid -> {:error, :rejected}
    end
  end

  defp arming_budget(request, execution) do
    remaining =
      execution.deadline_ms - System.monotonic_time(:millisecond) -
        request.duration_seconds * 1_000 - Request.settlement_grace_ms()

    min(Request.arming_timeout_ms(), remaining)
  end

  defp current?(wait, state) do
    TextCapability.current?(state, wait.coordinator) and
      state.text_capability.activation_id == wait.activation_id and
      MapSet.member?(state.participant_ids, wait.context.source_participant_id) and
      not State.conversation_held?(state, wait.context.source_participant_id) and
      Map.has_key?(state.connections, wait.context.connection_id)
  end

  defp start_quiet(%State{idle_wait: wait} = state) do
    cancel_timer(wait.timer)

    timer =
      Process.send_after(
        self(),
        {:vxpipe_idle_wait_deadline, wait.token, :quiet},
        wait.duration_ms
      )

    %{state | idle_wait: %{wait | phase: :quiet, timer: timer}}
  end

  defp expire(%State{idle_wait: wait} = state) do
    case IdleNotification.new(state, wait.context.connection_id) do
      {:ok, command} ->
        send(wait.coordinator, {:vxpipe_idle_expired, self(), wait.token, command})
        reply_and_release(wait, {:ok, %{"status" => "expired"}})

        wait = %{
          wait
          | phase: :expiring,
            timer: nil,
            from: nil,
            worker_monitor: nil,
            timeout_command: command
        }

        state |> Map.put(:idle_wait, wait) |> TurnState.put(command)

      {:error, _reason} ->
        cancel(state, :source_replaced)
    end
  end

  defp finish(state) do
    if state.call_lifecycle, do: CallLifecycle.activity(state.call_lifecycle)
    %{state | idle_wait: nil}
  end

  defp reply_and_release(wait, result) do
    cancel_timer(wait.timer)
    if wait.worker_monitor, do: Process.demonitor(wait.worker_monitor, [:flush])
    if wait.from, do: GenServer.reply(wait.from, result)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)
end
