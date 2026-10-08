defmodule Vxpipe.Providers.Google.STSResumption do
  @moduledoc """
  Bounded, same-allocation Google Live reconnection using private server handles.

  Only idle, playback-settled checkpoints are resumed. Old input is never
  replayed, and a failed attempt never falls back to a fresh conversation.
  """

  alias Vxpipe.Providers.Google.{STS, STSResponses}

  def valid_timeout?(resume), do: is_integer(resume) and resume in 1..15_000

  # PCM may precede provider onset, so it invalidates idle but does not prove a
  # new model turn or manufacture overlapping model ownership.
  def invalidate_idle(state),
    do: %{state | interaction_status: :unknown}

  def accept_audio(state, audio) do
    if silent?(audio) do
      state
    else
      %{state | clean_input_boundary?: state.clean_input_boundary? or clean_boundary?(state)}
      |> invalidate_idle()
      |> await_model_activity()
      |> await_audio_final()
    end
  end

  # Digital silence still reaches the provider, but cannot start a caller turn.
  # No amplitude threshold is used: even one nonzero sample dirties the checkpoint.
  defp silent?(<<0::64, rest::binary>>), do: silent?(rest)
  defp silent?(<<0::16, rest::binary>>), do: silent?(rest)
  defp silent?(<<>>), do: true
  defp silent?(_audio), do: false

  def await_model_activity(state),
    do: %{state | awaiting_model_activity?: true}

  def observe_handle(%{retiring_wire: wire} = state, handle) when is_pid(wire),
    do: %{state | pending_handle: handle}

  def observe_handle(state, handle), do: %{state | resumption_handle: handle}

  def await_audio_final(%{response_start?: true, caller: %{ended?: true}} = state),
    do: %{state | awaiting_audio_final?: true, audio_after_caller_end?: true}

  def await_audio_final(%{response_start?: true} = state),
    do: %{state | awaiting_audio_final?: true}

  def await_audio_final(state), do: state

  def observed_caller_final(state),
    do: %{
      state
      | awaiting_audio_final?: state.audio_after_caller_end?,
        audio_after_caller_end?: false
    }

  def observed_model_content(state),
    do: %{model_work(state) | awaiting_model_activity?: false, clean_model_content?: true}

  def model_work(state),
    do: %{invalidate_idle(state) | model_turn_complete?: false, clean_input_boundary?: false}

  def begin_turn(state) do
    clean? =
      (clean_boundary?(state) or state.clean_input_boundary?) and is_nil(state.caller) and
        map_size(state.pending_tools) == 0 and output_idle?(state)

    %{
      state
      | model_turn_complete?: false,
        interaction_status: :unknown,
        resumption_ambiguous?: state.resumption_ambiguous? or not state.model_turn_complete?,
        clean_exchange?: clean?,
        clean_input_boundary?: false,
        clean_model_content?: false
    }
  end

  def recoverable?(state),
    do:
      not state.resumption_ambiguous? and settled_boundary?(state) and
        is_binary(state.resumption_handle)

  def request(state, remaining_ms \\ nil)

  def request(%{renew_requested?: true} = state, nil), do: advance(state)

  def request(%{renew_requested?: true} = state, remaining_ms) do
    deadline = min(state.resume_deadline, now_ms() + remaining_ms)
    state |> arm_deadline(deadline) |> advance()
  end

  def request(state, remaining_ms) do
    now = now_ms()

    budget =
      if is_integer(remaining_ms), do: max(remaining_ms, 0), else: state.resumption_timeout_ms

    reason = if is_integer(remaining_ms), do: :go_away, else: :connection_lost

    %{state | renew_requested?: true, rotation_reason: reason}
    |> arm_deadline(now + budget)
    |> advance()
  end

  def advance(state) do
    state = clear_clean_ambiguity(state)

    if state.renew_requested? and not state.resuming? and recoverable?(state),
      do: start_replacement(state),
      else: state
  end

  defp clear_clean_ambiguity(state) do
    if state.clean_exchange? and state.clean_model_content? and settled_boundary?(state) do
      %{state | resumption_ambiguous?: false, clean_exchange?: false, clean_model_content?: false}
    else
      state
    end
  end

  def connected(state) do
    setup =
      state.config
      |> STS.setup()
      |> put_in(["setup", "sessionResumption"], %{"handle" => state.pending_handle})

    state.wire_module.send_control(state.pending_wire, JSON.encode!(setup))
  end

  def complete(state) do
    if state.resume_timer, do: Process.cancel_timer(state.resume_timer)

    :telemetry.execute(
      [:vxpipe, :providers, :google, :sts, :resumed],
      %{count: 1},
      %{reason: state.rotation_reason}
    )

    state
    |> Map.merge(%{
      wire: state.pending_wire,
      wire_monitor: state.pending_monitor,
      pending_wire: nil,
      pending_monitor: nil,
      pending_handle: nil,
      resumption_handle: nil,
      renew_requested?: false,
      resuming?: false,
      resume_attempt: nil,
      resume_timer: nil,
      resume_deadline: nil,
      rotation_reason: nil
    })
  end

  def start_socket(state, extra) do
    options =
      [
        owner: self(),
        connection: STS.connection_options(state.config),
        transport_options: state.wire_options
      ] ++ extra

    DynamicSupervisor.start_child(state.socket_supervisor, %{
      id: state.wire_module,
      start: {state.wire_module, :start_link, [options]},
      restart: :temporary,
      shutdown: :brutal_kill
    })
  end

  defp start_replacement(state) do
    deadline = min(state.resume_deadline, now_ms() + state.resumption_timeout_ms)
    state = arm_deadline(state, deadline)

    state = %{
      state
      | retiring_wire: state.wire,
        resuming?: true,
        pending_handle: state.resumption_handle,
        resumption_handle: nil
    }

    if state.rotation_reason == :connection_lost do
      case retired(state) do
        {:ok, next} ->
          next

        {:error, _reason} ->
          send(self(), :resumption_unsafe)
          state
      end
    else
      :ok = state.wire_module.retire(state.wire)
      state
    end
  end

  def retired(state) do
    if not state.resumption_ambiguous? and settled_boundary?(state) and
         is_binary(state.pending_handle) and now_ms() < state.resume_deadline do
      open_replacement(state)
    else
      {:error, :unsafe_checkpoint}
    end
  end

  def retry_replacement(state) do
    if now_ms() < state.resume_deadline and is_binary(state.pending_handle) do
      if state.pending_monitor, do: Process.demonitor(state.pending_monitor, [:flush])
      state = %{state | pending_wire: nil, pending_monitor: nil, retry_pending?: false}
      connect_replacement(state)
    else
      {:error, :resumption_expired}
    end
  end

  defp open_replacement(state) do
    if state.wire_monitor, do: Process.demonitor(state.wire_monitor, [:flush])
    _ = DynamicSupervisor.terminate_child(state.socket_supervisor, state.wire)
    state = %{state | wire: nil, wire_monitor: nil, retiring_wire: nil, retirement_ack?: false}

    connect_replacement(state)
  end

  defp connect_replacement(state) do
    case start_socket(state, deferred: true) do
      {:ok, pending} ->
        {:ok, %{state | pending_wire: pending, pending_monitor: Process.monitor(pending)}}

      _failure ->
        {:error, :connection_unavailable}
    end
  end

  def quiescent?(state) do
    not state.resumption_ambiguous? and state.interaction_status == :idle and
      settled_boundary?(state)
  end

  defp settled_boundary?(state) do
    not state.awaiting_model_activity? and not state.awaiting_audio_final? and
      state.model_turn_complete? and
      state.interaction_status in [:idle, :omitted] and is_nil(state.caller) and
      map_size(state.pending_tools) == 0 and output_idle?(state)
  end

  # An interrupted exchange may never produce model content. Its stale
  # awaiting-model flag must not prevent a subsequent, attributable exchange
  # from repairing ambiguity. It still cannot authorize a socket rotation.
  defp clean_boundary?(state) do
    settled_boundary?(state) or
      (state.resumption_ambiguous? and not state.awaiting_audio_final? and
         state.model_turn_complete? and state.interaction_status in [:idle, :omitted] and
         is_nil(state.caller) and map_size(state.pending_tools) == 0 and output_idle?(state))
  end

  def input_quiescent?(state),
    do: state.ready? and is_pid(state.wire) and not state.resuming? and quiescent?(state)

  defp output_idle?(%{response_start?: true} = state), do: STSResponses.idle?(state.responses)

  defp output_idle?(state),
    do: is_nil(state.input_turn) and is_nil(state.output) and state.audio_buffer == []

  defp arm_deadline(state, deadline) do
    if state.resume_timer, do: Process.cancel_timer(state.resume_timer)
    attempt = make_ref()

    timer =
      Process.send_after(self(), {:resumption_timeout, attempt}, max(deadline - now_ms(), 0))

    %{state | resume_attempt: attempt, resume_timer: timer, resume_deadline: deadline}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
