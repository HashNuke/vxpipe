defmodule Vxpipe.Gateway.WebRTC.Connection.SourceCutover do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.WebRTC.SourceReceiver

  # ExWebRTC's controlling_process call can occupy five seconds. Leave a
  # bounded margin for the receiver marker and Connection reply.
  @maximum_budget_ms 8_000

  def hold(scope, caller, state) do
    with :ok <- authorize(scope, caller, state),
         :ok <- available_source(state),
         :ok <- valid_hold(scope, state),
         {:ok, remaining} <- remaining_budget(scope.deadline_ms) do
      held_epoch = make_ref()
      gate = %{held?: true, token: scope.token, receipt: nil, status: :cutting_over}
      held = Map.put(state, :source_gate, gate)

      case SourceReceiver.cutover(
             state.source_receiver,
             state.source_epoch,
             held_epoch,
             remaining
           ) do
        :ok ->
          if before_deadline?(scope.deadline_ms) do
            receipt = %{
              attachment: scope.attachment,
              token: scope.token,
              receiver: state.source_receiver,
              old_epoch: state.source_epoch,
              held_epoch: held_epoch
            }

            {:ok, receipt,
             %{
               held
               | source_epoch: held_epoch,
                 source_gate: %{gate | receipt: receipt, status: :held}
             }}
          else
            uncertain(held)
          end

        {:error, _reason} ->
          uncertain(held)
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def arm(scope, caller, state) do
    with :ok <- authorize(scope, caller, state),
         :ok <- available_source(state),
         :ok <- valid_arm(scope, state) do
      case {transfer_clear(state), remaining_budget(scope.deadline_ms)} do
        {:ok, {:ok, remaining}} ->
          rotate_active(scope, state, remaining)

        {{:error, reason}, _budget} ->
          {:error, reason, terminal(state)}

        {:ok, {:error, reason}} ->
          {:error, reason, terminal(state)}
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp rotate_active(scope, state, remaining) do
    case SourceReceiver.cutover(
           state.source_receiver,
           state.source_epoch,
           scope.active_epoch,
           remaining
         ) do
      :ok ->
        if before_deadline?(scope.deadline_ms) do
          active = %{held?: false, token: scope.token, receipt: nil, status: :active}

          {:ok, scope.active_epoch,
           %{state | source_epoch: scope.active_epoch, source_gate: active}}
        else
          uncertain(state)
        end

      {:error, _reason} ->
        uncertain(state)
    end
  end

  defp authorize(
         %{attachment: attachment},
         caller,
         %{
           attachment: %ConnectionAttachment{
             admission: :main,
             room_authority: authority,
             room_monitor: monitor
           }
         }
       )
       when is_pid(authority) and caller == authority and attachment == monitor,
       do: :ok

  defp authorize(_scope, _caller, _state), do: {:error, :unauthorized}

  defp available_source(%{source_receiver: receiver, source_epoch: epoch})
       when is_pid(receiver) and is_reference(epoch),
       do: :ok

  defp available_source(_state), do: {:error, :stale_source}

  defp valid_hold(%{token: token}, state) when is_reference(token) do
    case Map.get(state, :source_gate) do
      nil -> :ok
      %{held?: false, token: ^token} -> {:error, :stale_source}
      %{held?: false} -> :ok
      _held -> {:error, :stale_source}
    end
  end

  defp valid_hold(_scope, _state), do: {:error, :stale_source}

  defp valid_arm(
         %{token: token, receipt: %{old_epoch: old_epoch} = receipt, active_epoch: active_epoch},
         %{
           source_gate: %{held?: true, status: :held, token: token, receipt: receipt},
           source_receiver: receiver,
           source_epoch: held_epoch
         }
       )
       when is_reference(token) and is_reference(active_epoch) and
              active_epoch != held_epoch and active_epoch != old_epoch do
    if receipt.receiver == receiver and receipt.held_epoch == held_epoch and
         receipt.token == token,
       do: :ok,
       else: {:error, :stale_source}
  end

  defp valid_arm(_scope, _state), do: {:error, :stale_source}

  defp transfer_clear(state) do
    if match?(%{held?: true}, Map.get(state, :handoff_gate)),
      do: {:error, :transfer_held},
      else: :ok
  end

  defp remaining_budget(deadline) when is_integer(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 and remaining <= @maximum_budget_ms,
      do: {:ok, remaining},
      else: {:error, :deadline_elapsed}
  end

  defp remaining_budget(_invalid), do: {:error, :deadline_elapsed}

  defp before_deadline?(deadline),
    do: System.monotonic_time(:millisecond) < deadline

  defp uncertain(state) do
    {:error, :source_unavailable, terminal(state)}
  end

  defp terminal(state) do
    gate = %{state.source_gate | held?: true, receipt: nil, status: :uncertain}
    %{state | source_gate: gate}
  end
end
