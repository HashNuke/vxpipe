defmodule Vxpipe.CallEngine.RoomAuthority.ActionAnnouncement do
  @moduledoc "Room-owned playback reservation preceding a hangup or participant transfer."

  alias Vxpipe.CallEngine.{AgentActivationSupervisor, Id, TextToSpeechRequest}
  alias Vxpipe.CallEngine.Archive.Recorder

  alias Vxpipe.CallEngine.RoomAuthority.{
    CallerIdle,
    EndCall,
    EventPublisher,
    ParticipantTransfer,
    State
  }

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Authorizer
  alias Vxpipe.CallEngine.Tool.{Announcement, Hangup, InvocationRegistry}

  @derive {Inspect, only: [:phase]}
  defstruct [
    :action,
    :request,
    :capability,
    :connection,
    :timer,
    :worker_monitor,
    :connection_monitor,
    :registry,
    :request_id,
    :phase
  ]

  @type t :: %__MODULE__{}

  def hangup(context, text, from, state) do
    with true <- available?(state),
         %{activation_id: activation_id} <- state.text_capability,
         registry =
           AgentActivationSupervisor.child_ref(
             activation_id,
             :invocation_registry
           ),
         {:ok, execution} <-
           InvocationRegistry.running_execution(
             registry,
             context.tool_call_id
           ),
         %{context: ^context, binding: %{handler: {:platform, Hangup}}} <-
           execution,
         {:ok, ^text, rest} when map_size(rest) == 0 <- Announcement.extract(execution.arguments),
         :ok <- EndCall.authorize(execution.completion_target, context, state),
         :ok <-
           InvocationRegistry.hold_accepted_hangup(
             registry,
             context.tool_call_id,
             execution.worker
           ) do
      start({:hangup, execution.completion_target, context, registry, from}, context, text, state)
    else
      _stale_or_busy -> {:reply, {:error, :rejected}, state}
    end
  end

  def transfer(request, from, state) do
    with :ok <- Authorizer.authorize(request, state),
         true <- available?(state) do
      start({:transfer, request, from}, request, request.announcement, state)
    else
      _stale_or_busy -> {:reply, {:error, :rejected}, state}
    end
  end

  defp available?(state) do
    state.action_announcement == nil and state.pending_participant_transfer == nil and
      MapSet.size(state.held_participant_ids) == 0
  end

  defp start(action, context, text, state) do
    connection = Map.fetch!(state.connections, context.connection_id)

    case {state.text_to_speech_capability, connection.output_sink} do
      {%{pid: capability, participant_id: speaker}, sink}
      when is_pid(capability) and is_pid(sink) ->
        request = %TextToSpeechRequest{
          purpose: :action_announcement,
          tenant_id: context.tenant_id,
          room_id: context.room_id,
          incarnation_id: context.incarnation_id,
          participant_id: speaker,
          source_participant_id: connection.participant_id,
          connection_id: context.connection_id,
          command_id: context.command_id,
          correlation_id: Id.generate(:turn),
          output_id: Id.generate(:event),
          source_policy: EventPublisher.transcript_source_policy(state, speaker),
          text: text,
          output_sink: sink,
          output_generation: Map.get(connection, :output_generation, 0)
        }

        timer =
          Process.send_after(
            self(),
            {:announcement_deadline, request.output_id},
            Announcement.budget_ms()
          )

        pending = %__MODULE__{
          action: action,
          request: request,
          capability: capability,
          connection: output_binding(connection),
          timer: timer,
          phase: :synthesizing,
          connection_monitor: Process.monitor(connection.pid),
          worker_monitor: monitor_worker(action),
          request_id: :gen_server.send_request(capability, {:synthesize, request})
        }

        {:noreply, CallerIdle.reconcile(%{state | action_announcement: pending})}

      _unavailable ->
        perform(action, state)
    end
  end

  def playback(
        capability,
        request,
        status,
        %State{action_announcement: %{capability: capability, request: request} = pending} = state
      ) do
    case {status, pending.phase} do
      {:completed, :playing} ->
        drain = :gen_server.send_request(request.output_sink, :vxpipe_audio_output_drain)

        {:noreply,
         %{state | action_announcement: %{pending | request_id: drain, phase: :draining}}}

      {:discarded, phase} when phase in [:synthesizing, :playing] ->
        finish(state)

      _progress ->
        {:noreply, state}
    end
  end

  def playback(_capability, _request, _status, state), do: {:noreply, state}

  def response(message, %{action_announcement: pending} = state) do
    case {:gen_server.check_response(message, pending.request_id), pending.phase} do
      {{:reply, :ok}, :synthesizing} ->
        {:noreply, %{state | action_announcement: %{pending | phase: :playing, request_id: nil}}}

      {{:reply, :ok}, :draining} ->
        finish(state, :delivered)

      {:no_reply, _phase} ->
        {:noreply, state}

      _settled ->
        finish(state)
    end
  end

  def renderer_unavailable(state) do
    # A connection-wide failure notification can close the carrier before it drains.
    # The admitted action owns the fallback while the original sink is still valid.
    Process.demonitor(state.text_to_speech_capability.monitor, [:flush])
    state = %{state | text_to_speech_capability: nil}

    if state.action_announcement.phase == :draining, do: {:noreply, state}, else: finish(state)
  end

  def deadline(
        {:settle, id},
        %{
          action_announcement: %{
            phase: :settling,
            action: {capability, %{tool_call_id: id} = context}
          }
        } = state
      ),
      do: settle_hangup(capability, context, state)

  def deadline(id, %{action_announcement: %{request: %{output_id: id}} = pending} = state) do
    interrupt(pending)
    finish(state)
  end

  def deadline(_id, state), do: {:noreply, state}

  def cancel(%{action_announcement: %{phase: :settling} = pending} = state),
    do: resume(pending, release(state))

  def cancel(%{action_announcement: pending} = state) do
    interrupt(pending)
    reject(pending.action, release(state))
  end

  defp interrupt(%{phase: :draining}), do: :ok

  defp interrupt(pending) do
    # Queued behind synthesis admission even if the deadline beat its acknowledgement.
    id = :gen_server.send_request(pending.capability, {:interrupt, [pending.request]})
    :gen_server.receive_response(id, 0)
  end

  defp finish(%{action_announcement: pending} = state, outcome \\ :unconfirmed) do
    state = release(state)
    connection = Map.get(state.connections, pending.request.connection_id)

    if output_binding(connection) == pending.connection do
      perform(pending.action, record_delivery(state, pending.request, outcome))
    else
      reject(pending.action, state)
    end
  end

  defp record_delivery(state, request, :delivered) do
    %{state | archive_recorder: Recorder.delivered_output(state.archive_recorder, request)}
  end

  defp record_delivery(state, _request, :unconfirmed), do: state

  defp perform({:hangup, capability, context, registry, from}, state) do
    # Keep the room held until the registry publishes the tool result and its effect.
    # A lost worker cannot strand an already accepted terminal action.
    connection = Map.fetch!(state.connections, context.connection_id)

    timer =
      Process.send_after(self(), {:announcement_deadline, {:settle, context.tool_call_id}}, 1_000)

    pending = %__MODULE__{
      phase: :settling,
      registry: registry,
      action: {capability, context},
      timer: timer,
      connection: output_binding(connection),
      connection_monitor: Process.monitor(connection.pid)
    }

    GenServer.reply(from, :ok)
    {:noreply, %{state | action_announcement: pending}}
  end

  defp perform({:transfer, request, from}, state) do
    case ParticipantTransfer.begin(%{request | announcement: nil}, from, state) do
      {:reply, result, state} ->
        GenServer.reply(from, result)
        {:noreply, CallerIdle.reconcile(state)}

      {:noreply, state} ->
        {:noreply, CallerIdle.reconcile(state)}
    end
  end

  def settle_hangup(
        capability,
        context,
        %{action_announcement: %{phase: :settling, action: {capability, context}} = pending} =
          state
      ) do
    state = release(state)
    connection = Map.get(state.connections, context.connection_id)

    if output_binding(connection) == pending.connection and
         EndCall.authorize(capability, context, state) == :ok do
      {:stop, {:shutdown, :agent_hangup}, state}
    else
      resume(pending, state)
    end
  end

  def settle_hangup(_capability, _context, state), do: {:noreply, state}

  defp resume(%{registry: registry, action: {_capability, context}}, state) do
    InvocationRegistry.resume_after_announcement(registry, context.tool_call_id)
    {:noreply, CallerIdle.reconcile(state)}
  end

  defp output_binding(nil), do: nil

  defp output_binding(connection),
    do: {connection.pid, connection.output_sink, Map.get(connection, :output_generation, 0)}

  defp reject({:transfer, _request, from}, state) do
    GenServer.reply(from, {:error, :rejected})
    {:noreply, CallerIdle.reconcile(state)}
  end

  defp reject({:hangup, _capability, context, registry, from}, state) do
    InvocationRegistry.resume_after_announcement(registry, context.tool_call_id)
    GenServer.reply(from, {:error, :rejected})
    {:noreply, CallerIdle.reconcile(state)}
  end

  defp release(%{action_announcement: pending} = state) do
    Process.cancel_timer(pending.timer)
    Process.demonitor(pending.connection_monitor, [:flush])
    if pending.worker_monitor, do: Process.demonitor(pending.worker_monitor, [:flush])
    if pending.request_id, do: :gen_server.receive_response(pending.request_id, 0)

    %{state | action_announcement: nil}
  end

  defp monitor_worker({:transfer, _request, {worker, _tag}}), do: Process.monitor(worker)
  defp monitor_worker(_hangup), do: nil
end
