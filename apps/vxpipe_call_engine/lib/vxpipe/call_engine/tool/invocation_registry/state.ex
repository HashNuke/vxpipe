defmodule Vxpipe.CallEngine.Tool.InvocationRegistry.State do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{InvocationRecord, InvocationSubmission}

  @derive {Inspect, only: [:maximum_invocations, :maximum_consumed_invocations]}
  @enforce_keys [
    :invocation_supervisor,
    :completion_target,
    :lifecycle_target,
    :maximum_invocations,
    :maximum_consumed_invocations,
    :invocation_timeout_ms,
    :maximum_result_bytes,
    :usage
  ]
  defstruct @enforce_keys ++ [records: %{}, order: [], consumed: MapSet.new(), consumed_order: []]

  @type t :: %__MODULE__{}

  @spec full?(t()) :: boolean()
  def full?(%__MODULE__{} = state), do: map_size(state.records) >= state.maximum_invocations

  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = state), do: map_size(state.records)

  @spec completion_depth(t()) :: non_neg_integer()
  def completion_depth(%__MODULE__{} = state) do
    Enum.count(state.records, fn {_invocation_id, record} ->
      record.status == :terminal_queued
    end)
  end

  @spec consumed?(t(), String.t()) :: boolean()
  def consumed?(%__MODULE__{} = state, invocation_id) do
    MapSet.member?(state.consumed, invocation_id)
  end

  @spec fetch(t(), String.t()) :: {:ok, InvocationRecord.t()} | :error
  def fetch(%__MODULE__{} = state, invocation_id), do: Map.fetch(state.records, invocation_id)

  @spec add(t(), InvocationRecord.t()) :: t()
  def add(%__MODULE__{} = state, %InvocationRecord{} = record) do
    %{
      state
      | records: Map.put(state.records, record.invocation_id, record),
        order: state.order ++ [record.invocation_id]
    }
  end

  @spec replace(t(), InvocationRecord.t()) :: t()
  def replace(%__MODULE__{} = state, %InvocationRecord{} = record) do
    %{state | records: Map.put(state.records, record.invocation_id, record)}
  end

  @spec statuses(t()) :: [Vxpipe.CallEngine.Tool.InvocationStatus.t()]
  def statuses(%__MODULE__{} = state) do
    Enum.map(state.order, fn invocation_id ->
      state.records |> Map.fetch!(invocation_id) |> InvocationRecord.status()
    end)
  end

  @spec next_terminal(t()) :: {:ok, InvocationRecord.t()} | :empty
  def next_terminal(%__MODULE__{} = state) do
    case Enum.find_value(state.order, fn invocation_id ->
           case Map.fetch!(state.records, invocation_id) do
             %InvocationRecord{status: :terminal_queued} = record -> record
             _other -> nil
           end
         end) do
      %InvocationRecord{} = record -> {:ok, record}
      nil -> :empty
    end
  end

  @spec find_by_monitor(t(), reference()) :: {:ok, InvocationRecord.t()} | :error
  def find_by_monitor(%__MODULE__{} = state, monitor) do
    case Enum.find(Map.values(state.records), &(&1.monitor == monitor)) do
      %InvocationRecord{} = record -> {:ok, record}
      nil -> :error
    end
  end

  @spec consume(t(), InvocationRecord.t()) :: t()
  def consume(%__MODULE__{} = state, %InvocationRecord{} = record) do
    state = %{
      state
      | records: Map.delete(state.records, record.invocation_id),
        order: Enum.reject(state.order, &(&1 == record.invocation_id)),
        consumed: MapSet.put(state.consumed, record.invocation_id),
        consumed_order: state.consumed_order ++ [record.invocation_id]
    }

    trim_consumed(state)
  end

  @spec submission_outcome(t(), InvocationSubmission.t()) ::
          {:accepted, :blocking | :non_blocking} | {:error, :rejected | :unavailable}
  def submission_outcome(%__MODULE__{} = state, %InvocationSubmission{} = submission) do
    cond do
      consumed?(state, submission.invocation_id) ->
        {:error, :rejected}

      match?({:ok, _record}, fetch(state, submission.invocation_id)) ->
        {:ok, record} = fetch(state, submission.invocation_id)

        if InvocationRecord.same_submission?(record, submission) do
          {:accepted, record.conversation_mode}
        else
          {:error, :rejected}
        end

      true ->
        {:error, :unavailable}
    end
  end

  defp trim_consumed(state) do
    excess = length(state.consumed_order) - state.maximum_consumed_invocations

    if excess > 0 do
      {expired, retained} = Enum.split(state.consumed_order, excess)
      consumed = Enum.reduce(expired, state.consumed, &MapSet.delete(&2, &1))
      %{state | consumed: consumed, consumed_order: retained}
    else
      state
    end
  end
end
