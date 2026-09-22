defmodule Vxpipe.CallEngine.Speech.ResponseStarts do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Event

  @maximum_pending 16
  @maximum_index 9_223_372_036_854_775_807

  @derive {Inspect, only: [:high_water]}
  defstruct high_water: 0, pending: %{}

  def new, do: %__MODULE__{}
  def pending_count(owner), do: map_size(owner.pending)

  def accept(
        %__MODULE__{} = owner,
        %Event{
          kind: :response_started,
          turn_ref: turn,
          response_index: index,
          response_context: context
        }
      )
      when is_reference(turn) and is_reference(context) and is_integer(index) and
             index in 1..@maximum_index do
    cond do
      owner.high_water >= @maximum_index ->
        {:error, :response_overflow}

      index <= owner.high_water ->
        {:error, :stale_response}

      Map.has_key?(owner.pending, turn) ->
        {:error, :stale_response}

      pending_count(owner) >= @maximum_pending ->
        {:error, :response_overflow}

      true ->
        response = %{index: index, context: context, acked?: false}
        {:ok, %{owner | high_water: index, pending: Map.put(owner.pending, turn, response)}}
    end
  end

  def accept(_owner, _event), do: {:error, :stale_response}

  def acknowledge(%__MODULE__{} = owner, %Event{kind: :response_started} = event) do
    case Map.fetch(owner.pending, event.turn_ref) do
      {:ok, %{index: index, context: context, acked?: false} = response}
      when index == event.response_index and context == event.response_context ->
        pending = Map.put(owner.pending, event.turn_ref, %{response | acked?: true})
        {:ok, %{owner | pending: pending}}

      _other ->
        {:error, :stale_response}
    end
  end

  def acknowledge(_owner, _event), do: {:error, :stale_response}

  def grant(%__MODULE__{} = owner, turn) when is_reference(turn) do
    case Map.fetch(owner.pending, turn) do
      {:ok, %{acked?: false}} ->
        {:error, :response_not_acknowledged}

      {:ok, %{index: index, context: context}} ->
        if index == oldest_index(owner) do
          {:ok, %{owner | pending: Map.delete(owner.pending, turn)}, context}
        else
          {:error, :busy}
        end

      :error ->
        {:error, :stale_response}
    end
  end

  def grant(_owner, _turn), do: {:error, :stale_response}

  def reject(%__MODULE__{} = owner, turn) when is_reference(turn) do
    case Map.fetch(owner.pending, turn) do
      {:ok, %{acked?: true, context: context}} ->
        {:ok, %{owner | pending: Map.delete(owner.pending, turn)}, context}

      {:ok, _unacknowledged} ->
        {:error, :response_not_acknowledged}

      :error ->
        {:error, :stale_response}
    end
  end

  def reject(_owner, _turn), do: {:error, :stale_response}

  defp oldest_index(owner) do
    owner.pending
    |> Map.values()
    |> Enum.min_by(& &1.index)
    |> Map.fetch!(:index)
  end
end
