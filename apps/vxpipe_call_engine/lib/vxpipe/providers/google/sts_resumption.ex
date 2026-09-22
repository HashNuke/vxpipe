defmodule Vxpipe.Providers.Google.STSResumption do
  @moduledoc """
  Bounded, same-allocation Google Live reconnection using private server handles.

  Only idle, playback-settled checkpoints are resumed. Old input is never
  replayed, and a failed attempt never falls back to a fresh conversation.
  """

  alias Vxpipe.Providers.Google.STS

  def valid_deadlines?(renew, expire, resume) do
    is_integer(renew) and is_integer(expire) and is_integer(resume) and
      renew > 0 and expire > renew and expire <= 600_000 and resume in 1..15_000
  end

  def invalidate(state), do: %{state | resumption_handle: nil}

  def recoverable?(state), do: idle?(state) and is_binary(state.resumption_handle)

  def request(state, remaining_ms \\ nil)

  def request(%{renew_requested?: true} = state, nil), do: advance(state)

  def request(%{renew_requested?: true} = state, remaining_ms) do
    deadline = min(state.resume_deadline, now_ms() + remaining_ms)
    state |> arm_deadline(deadline) |> advance()
  end

  def request(state, remaining_ms) do
    if state.renew_timer, do: Process.cancel_timer(state.renew_timer)

    now = now_ms()
    available = max(state.expire_deadline - now, 0)
    available = if is_integer(remaining_ms), do: min(available, remaining_ms), else: available
    budget = if idle?(state), do: min(available, state.resumption_timeout_ms), else: available

    %{state | renew_requested?: true, renew_timer: nil}
    |> arm_deadline(now + budget)
    |> advance()
  end

  def advance(%{renew_requested?: true, resuming?: false} = state) do
    if recoverable?(state), do: start_replacement(state), else: state
  end

  def advance(state), do: state

  def connected(state) do
    setup =
      state.config
      |> STS.setup()
      |> put_in(["setup", "sessionResumption"], %{"handle" => state.pending_handle})

    state.wire_module.send_control(state.pending_wire, JSON.encode!(setup))
  end

  def complete(state) do
    if state.resume_timer, do: Process.cancel_timer(state.resume_timer)
    if state.expire_timer, do: Process.cancel_timer(state.expire_timer)

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
      resume_deadline: nil
    })
    |> schedule_renewal()
  end

  def schedule_renewal(state) do
    if state.renew_timer, do: Process.cancel_timer(state.renew_timer)
    if state.expire_timer, do: Process.cancel_timer(state.expire_timer)

    %{
      state
      | renew_timer: Process.send_after(self(), {:renew, state.wire}, state.renew_after),
        expire_timer: Process.send_after(self(), {:expire, state.wire}, state.expire_after),
        expire_deadline: now_ms() + state.expire_after
    }
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
    if state.wire_monitor, do: Process.demonitor(state.wire_monitor, [:flush])

    # Retire through the owning supervisor. A protocol close would send
    # audioStreamEnd, changing the conversation after its checkpoint.
    if is_pid(state.wire) do
      _ = DynamicSupervisor.terminate_child(state.socket_supervisor, state.wire)
    end

    state = %{
      state
      | wire: nil,
        wire_monitor: nil,
        resuming?: true,
        pending_handle: state.resumption_handle,
        resumption_handle: nil
    }

    case start_socket(state, deferred: true) do
      {:ok, pending} ->
        %{state | pending_wire: pending, pending_monitor: Process.monitor(pending)}

      _failure ->
        send(self(), :resumption_unsafe)
        state
    end
  end

  defp idle?(state) do
    is_nil(state.input_turn) and is_nil(state.output) and state.audio_buffer == [] and
      map_size(state.pending_tools) == 0
  end

  defp arm_deadline(state, deadline) do
    if state.resume_timer, do: Process.cancel_timer(state.resume_timer)
    attempt = make_ref()

    timer =
      Process.send_after(self(), {:resumption_timeout, attempt}, max(deadline - now_ms(), 0))

    %{state | resume_attempt: attempt, resume_timer: timer, resume_deadline: deadline}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
