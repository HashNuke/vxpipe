defmodule Vxpipe.CallEngine.Readiness.RoomInventory do
  @moduledoc "Captures complete requirements and current bindings without admitting media."

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Candidate}
  alias Vxpipe.CallEngine.Readiness.Inventory
  alias Vxpipe.CallEngine.RoomAuthority

  @derive {Inspect, only: [:identity, :inventory]}
  @enforce_keys [:identity, :inventory, :room, :participants, :candidate, :binding]
  defstruct @enforce_keys

  # Run outside RoomAuthority. A single absolute budget bounds all binding/policy reads.
  def capture(room, %Candidate{} = candidate, timeout \\ 5_000)
      when is_integer(timeout) and timeout > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout

    with {:ok, binding} <- RoomAuthority.readiness_binding(room, remaining(deadline)),
         :ok <- validate_policy(binding, candidate, deadline),
         {:ok, captured} <- build(binding, candidate),
         :ok <- validate_until(room, captured, deadline) do
      {:ok, captured}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp build(binding, candidate) do
    options = Keyword.put(binding.options, :attempt_id, attempt_id(binding.attempt))

    with {:ok, inventory} <-
           Inventory.build(binding.plan, candidate.snapshot, binding.connections, options) do
      {:ok,
       %__MODULE__{
         identity: binding.identity,
         inventory: inventory,
         room: Map.take(binding.room, MapSet.to_list(inventory.room)),
         participants:
           Map.new(inventory.participant_capabilities, fn {id, kinds} ->
             {id, Map.take(Map.fetch!(binding.participants, id), MapSet.to_list(kinds))}
           end),
         candidate: candidate,
         binding: binding
       }}
    end
  end

  def validate(room, %__MODULE__{} = inventory, timeout \\ 5_000)
      when is_integer(timeout) and timeout > 0 do
    validate_until(room, inventory, System.monotonic_time(:millisecond) + timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp validate_until(room, captured, deadline) do
    with {:ok, binding} <- RoomAuthority.readiness_binding(room, remaining(deadline)),
         true <- binding == captured.binding,
         :ok <- validate_policy(binding, captured.candidate, deadline),
         {:ok, expected} <- build(binding, captured.candidate) do
      if expected == captured, do: :ok, else: {:error, :invalid_inventory}
    else
      false -> {:error, :room_changed}
      {:error, _reason} = error -> error
    end
  end

  defp validate_policy(
         %{policy_authority: authority},
         %{authority: authority} = candidate,
         deadline
       ),
       do: Authority.validate_candidate(authority, candidate, remaining(deadline))

  defp validate_policy(_binding, _candidate, _deadline), do: {:error, :invalid_candidate}

  defp attempt_id(nil), do: nil
  defp attempt_id(attempt), do: attempt.id

  defp remaining(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> min(remaining, 1_000)
      _expired -> exit(:readiness_inventory_timeout)
    end
  end
end
