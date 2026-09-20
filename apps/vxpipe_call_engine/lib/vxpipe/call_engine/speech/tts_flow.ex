defmodule Vxpipe.CallEngine.Speech.TTSFlow do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.{Allocation, Cancellation, Input, OutputState}

  def fence(state, command, reference) do
    ticket = %Cancellation{
      session: state.allocation,
      consumer: state.consumer,
      request_ref: reference,
      ref: make_ref(),
      deadline: command.deadline
    }

    if remaining(ticket) > 0 and Allocation.valid?(state.allocation) do
      case OutputState.fence(state.output, reference) do
        {:ok, awaiting, output} ->
          if awaiting, do: Process.cancel_timer(awaiting.timer)

          timer =
            Process.send_after(self(), {:cancellation_expired, ticket.ref}, remaining(ticket))

          cancellation = %{
            ticket: ticket,
            timer: timer,
            playback: nil,
            accepted?: false,
            pending: nil
          }

          {:ok, ticket, %{state | cancellation: cancellation, output: output}}

        _error ->
          {:error, :command_timeout}
      end
    else
      {:error, :command_timeout}
    end
  end

  def begin_cancel(state, command, played_ms, from) do
    reference = state.cancellation.ticket.request_ref

    case OutputState.record_playback(
           state.output,
           reference,
           played_ms,
           state.descriptor.format
         ) do
      {:ok, playback, output} ->
        cancellation = %{state.cancellation | playback: playback}
        state = %{state | cancellation: cancellation, output: output}
        route_cancel(state, command, from)

      error ->
        {:reply, error, state}
    end
  end

  def finish_cancel(state) do
    cancellation = %{state.cancellation | accepted?: true}

    case settle(%{state | cancellation: cancellation}) do
      {:ok, state} -> {:ok, state, {:ok, cancellation.playback}}
      :failed -> :failed
    end
  end

  def resume_pending(state, pending) do
    cancellation = %{state.cancellation | pending: nil}

    if remaining(pending.command) > 0 and remaining(cancellation.ticket) > 0 and
         Allocation.valid?(state.allocation),
       do: route_cancel(%{state | cancellation: cancellation}, pending.command, pending.from),
       else: :failed
  end

  def settle_rejected_pending(state, pending) do
    cancellation = %{state.cancellation | pending: nil, accepted?: true}

    case settle(%{state | cancellation: cancellation}) do
      {:ok, state} -> {:ok, state, {:ok, cancellation.playback}, pending}
      :failed -> :failed
    end
  end

  def settle(
        %{
          cancellation: %{accepted?: true} = cancellation,
          output: %OutputState{request: %{terminal?: true}}
        } = state
      ) do
    ticket = cancellation.ticket

    if remaining(ticket) > 0 and Allocation.valid?(state.allocation) do
      case OutputState.settle(state.output, ticket.request_ref) do
        {:ok, output} ->
          Process.cancel_timer(cancellation.timer)
          cached = Map.take(cancellation, [:ticket, :playback])
          {:ok, %{state | cancellation: nil, last_cancellation: cached, output: output}}

        _error ->
          :failed
      end
    else
      :failed
    end
  end

  def settle(state), do: {:ok, state}

  def reject(%{operation: {:speak, reference}} = command, {:error, _reason}, state) do
    if remaining(command) > 0 do
      case OutputState.reject(state.output, reference, not is_nil(state.cancellation)) do
        {:ok, output} -> {:ok, %{state | output: output}}
        _error -> :failed
      end
    else
      :failed
    end
  end

  def reject(_command, _result, state), do: {:ok, state}

  defp route_cancel(%{output: %OutputState{request: %{rejected?: true}}} = state, _command, _from) do
    cancellation = %{state.cancellation | accepted?: true}

    case settle(%{state | cancellation: cancellation}) do
      {:ok, state} -> {:reply, {:ok, cancellation.playback}, state}
      :failed -> :failed
    end
  end

  defp route_cancel(%{input: nil} = state, command, from) do
    if remaining(command) > 0 and Allocation.valid?(state.allocation) do
      reference = state.cancellation.ticket.request_ref
      command = Map.put(command, :operation, {:cancel, reference})
      timer = Process.send_after(self(), {:input_expired, command.ref}, remaining(command))
      input = %{command: command, from: from, timer: timer, claimed?: false}
      Input.submit(state.allocation, command, state.cancellation.playback)
      {:noreply, %{state | input: input}}
    else
      :failed
    end
  end

  defp route_cancel(state, command, from) do
    pending = %{command: command, from: from}
    cancellation = %{state.cancellation | pending: pending}
    {:noreply, %{state | cancellation: cancellation}}
  end

  defp remaining(command),
    do: max(command.deadline - System.monotonic_time(:millisecond), 0)
end
