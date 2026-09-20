defmodule Vxpipe.CallEngine.Speech.ChannelFailure do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Allocation, EventQueue, ProviderName, ScopeControl}

  def input_failed(state) do
    retire(state.allocation)
    reply_input(state.input, {:error, :session_failed})
    reply_pending_cancel(state.cancellation, {:error, :session_failed})
    ScopeControl.failed(state.allocation, :session_failed)
    {:stop, :normal, state}
  end

  def reply_pending_cancel(%{pending: pending}, reply) when not is_nil(pending),
    do: reply_input(pending, reply)

  def reply_pending_cancel(_cancellation, _reply), do: :ok

  def reply_input(nil, _reply), do: :ok
  def reply_input(%{from: nil}, _reply), do: :ok
  def reply_input(%{from: from}, reply), do: GenServer.reply(from, reply)

  def reply_after_ack(%{producer_down?: true, events: events} = state) do
    if EventQueue.idle?(events) do
      finish_producer_failure_drain(state)
      {:stop, :normal, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  def reply_after_ack(state), do: {:reply, :ok, state}

  def begin_producer_failure_drain(state) do
    if state.producer_monitor, do: Process.demonitor(state.producer_monitor, [:flush])
    if state.producer, do: Process.exit(state.producer, :kill)

    state = settle_draining_input(state)

    timer =
      state.producer_drain_timer ||
        Process.send_after(
          self(),
          {:producer_drain_expired, state.allocation.generation},
          state.call_timeout
        )

    %{
      state
      | producer: nil,
        producer_monitor: nil,
        producer_down?: true,
        producer_drain_timer: timer
    }
  end

  def finish_producer_failure_drain(state) do
    if state.producer_drain_timer, do: Process.cancel_timer(state.producer_drain_timer)
    retire(state.allocation)
    ScopeControl.failed(state.allocation, :session_failed)
    :ok
  end

  def drainable_stt_failure?(state) do
    state.descriptor.kind == :stt and EventQueue.pending_kind?(state.events, :turn_ended)
  end

  def retire(allocation) do
    Allocation.cancel(allocation)

    case ProviderName.whereis_name(allocation) do
      :undefined -> :ok
      pid -> Process.exit(pid, :kill)
    end
  end

  def fail(state, reason) do
    retire(state.allocation)
    ScopeControl.failed(state.allocation, reason)
    {:stop, :normal, {:error, reason}, state}
  end

  defp settle_draining_input(%{input: nil} = state), do: state

  defp settle_draining_input(%{input: input} = state) do
    Process.cancel_timer(input.timer)
    reply_input(input, {:error, :closed})
    %{state | input: nil}
  end
end
