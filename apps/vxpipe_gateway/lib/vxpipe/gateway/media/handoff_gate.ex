defmodule Vxpipe.Gateway.Media.HandoffGate do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.{Ingress, OutputSink}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase
  alias Vxpipe.Gateway.Media.RoomAudioEgress

  def pending(state, authority, attempt_id, output) do
    if Map.get(state, :handoff_gate) do
      {:ok, state}
    else
      # A new output starts at generation zero. Hold it before negotiation/input
      # can run; the handoff worker later installs the attempt's actual generation.
      with :ok <- OutputSink.hold(output, 1) do
        gate = %{
          scope: %{attempt_id: attempt_id},
          monitor: Process.monitor(authority),
          held?: true,
          pending?: true
        }

        {:ok, Map.put(state, :handoff_gate, gate)}
      end
    end
  end

  def hold(binding, scope) do
    gate_output(binding, scope, :hold)
  end

  def recover(binding, scope) do
    case gate_output(binding, scope, :recover) do
      {:error, reason} when reason in [:output_not_ready, :clearing] ->
        if System.monotonic_time(:millisecond) < scope.deadline_ms do
          receive do
          after
            10 -> recover(binding, scope)
          end
        else
          {:error, :deadline_elapsed}
        end

      result ->
        result
    end
  end

  defp gate_output(binding, scope, action) do
    with :ok <- request(binding, {action, scope}) do
      if binding.attachment.admission == :main and is_pid(binding.room_output),
        do: RoomAudioEgress.hold(binding.room_output, scope.generation),
        else: OutputSink.hold(binding.output, scope.generation)
    end
  end

  def release(binding, scope, demand) do
    result =
      if Keyword.fetch!(demand, :room_output?),
        do: RoomAudioEgress.release(binding.room_output, scope.generation),
        else: OutputSink.release(binding.output, scope.generation)

    with :ok <- result, do: request(binding, {:release, scope})
  end

  def adopt(binding, scope), do: request(binding, {:adopt, scope})

  def control(action, scope, caller, state) do
    with {:ok, phase} <- Phase.scope(scope.owner),
         true <- phase.attempt_id == scope.attempt_id and phase.deadline_ms == scope.deadline_ms,
         true <- phase.incarnation_id == state.attach_command.incarnation_id,
         %Task{pid: ^caller} <- Map.get(phase, :worker),
         true <- scope.deadline_ms > System.monotonic_time(:millisecond) do
      apply_control(action, scope, phase, state)
    else
      _invalid -> {:error, :stale_handoff}
    end
  end

  defp apply_control(:hold, scope, phase, state) do
    case Map.get(state, :handoff_gate) do
      nil ->
        gate = %{scope: scope, monitor: Process.monitor(phase.authority), held?: true}
        {:ok, Map.put(state, :handoff_gate, gate)}

      %{scope: ^scope, held?: true} ->
        {:ok, state}

      %{pending?: true, scope: %{attempt_id: attempt}, monitor: monitor}
      when attempt == scope.attempt_id ->
        Process.demonitor(monitor, [:flush])
        apply_control(:hold, scope, phase, Map.put(state, :handoff_gate, nil))

      _other ->
        {:error, :stale_handoff}
    end
  end

  defp apply_control(:recover, scope, %{stage: :recover} = phase, state) do
    case Map.get(state, :handoff_gate) do
      %{scope: %{attempt_id: attempt}, monitor: monitor} when attempt == scope.attempt_id ->
        Process.demonitor(monitor, [:flush])
        apply_control(:hold, scope, phase, %{state | handoff_gate: nil})

      nil ->
        apply_control(:hold, scope, phase, state)

      _stale ->
        {:error, :stale_handoff}
    end
  end

  defp apply_control(:adopt, scope, _phase, %{handoff_gate: %{scope: scope, held?: true}} = state) do
    attachment = %{
      state.attachment
      | admission: :main,
        transfer_attempt_id: nil,
        room_audio_input_mode: :enabled,
        room_audio_output_mode: state.private_media.output_mode
    }

    with :ok <- GenServer.call(state.room_audio_ingress, {:adopt_attachment, attachment}, 1_000),
         :ok <- GenServer.call(state.room_audio_egress, {:adopt_attachment, attachment}, 1_000) do
      {:ok, %{state | attachment: attachment}}
    end
  end

  defp apply_control(:release, scope, _phase, %{handoff_gate: %{scope: scope} = gate} = state) do
    result =
      if state.attachment.media_ingress,
        do: Ingress.open(state.attachment.media_ingress),
        else: :ok

    with :ok <- result do
      Process.demonitor(gate.monitor, [:flush])
      {:ok, %{state | handoff_gate: nil}}
    end
  end

  defp apply_control(_action, _scope, _phase, _state), do: {:error, :stale_handoff}

  defp request(binding, {action, scope}),
    do: GenServer.call(binding.instance, {:vxpipe_handoff_gate, action, scope}, 1_000)
end
