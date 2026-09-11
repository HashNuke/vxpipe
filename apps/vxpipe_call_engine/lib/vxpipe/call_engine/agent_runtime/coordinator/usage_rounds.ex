defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.UsageRounds do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.ActiveRequest
  alias Vxpipe.CallEngine.Id

  @enforce_keys [:requests]
  defstruct @enforce_keys

  @type round :: %{attempt_id: String.t(), tool_call_id: String.t() | nil}
  @type entry :: %{
          current: round() | nil,
          tool_call_id: String.t() | nil
        }
  @type t :: %__MODULE__{requests: %{optional(map()) => entry()}}

  @spec new() :: t()
  def new, do: %__MODULE__{requests: %{}}

  @spec register(t(), ActiveRequest.t()) :: t()
  def register(%__MODULE__{} = tracker, %ActiveRequest{} = request) do
    entry = %{
      current: nil,
      tool_call_id: tool_call_id(request)
    }

    %{tracker | requests: Map.put(tracker.requests, request.correlation, entry)}
  end

  @spec start(t(), map()) :: {:ok, t()} | {:error, :unknown_request | :attempt_in_progress}
  def start(%__MODULE__{} = tracker, correlation) when is_map(correlation) do
    case Map.fetch(tracker.requests, correlation) do
      {:ok, %{current: nil} = entry} ->
        round = %{attempt_id: Id.generate(:model_attempt), tool_call_id: entry.tool_call_id}
        entry = %{entry | current: round}
        {:ok, %{tracker | requests: Map.put(tracker.requests, correlation, entry)}}

      {:ok, %{current: %{} = _round}} ->
        {:error, :attempt_in_progress}

      :error ->
        {:error, :unknown_request}
    end
  end

  @spec finish(t(), map()) :: {:ok, round(), t()} | {:error, :unknown_attempt}
  def finish(%__MODULE__{} = tracker, correlation) when is_map(correlation) do
    case Map.fetch(tracker.requests, correlation) do
      {:ok, %{current: %{} = round} = entry} ->
        entry = %{entry | current: nil}
        {:ok, round, %{tracker | requests: Map.put(tracker.requests, correlation, entry)}}

      _unknown_or_idle ->
        {:error, :unknown_attempt}
    end
  end

  @spec complete(t(), map()) :: {round() | nil, t()}
  def complete(%__MODULE__{} = tracker, correlation) when is_map(correlation) do
    case Map.pop(tracker.requests, correlation) do
      {%{current: current}, requests} -> {current, %{tracker | requests: requests}}
      {nil, _requests} -> {nil, tracker}
    end
  end

  defp tool_call_id(%ActiveRequest{kind: {:completion, continuation}}),
    do: continuation.invocation_id

  defp tool_call_id(%ActiveRequest{}), do: nil
end
