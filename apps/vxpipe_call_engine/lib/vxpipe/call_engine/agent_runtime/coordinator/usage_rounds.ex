defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.UsageRounds do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.ActiveRequest

  @enforce_keys [:requests]
  defstruct @enforce_keys

  @type round :: %{attempt_id: String.t(), tool_call_id: String.t() | nil}
  @type entry :: %{
          command_id: String.t(),
          next_round: pos_integer(),
          tool_call_id: String.t() | nil
        }
  @type t :: %__MODULE__{requests: %{optional(map()) => entry()}}

  @spec new() :: t()
  def new, do: %__MODULE__{requests: %{}}

  @spec register(t(), ActiveRequest.t()) :: t()
  def register(%__MODULE__{} = tracker, %ActiveRequest{} = request) do
    entry = %{
      command_id: request.command.id,
      next_round: 1,
      tool_call_id: tool_call_id(request)
    }

    %{tracker | requests: Map.put(tracker.requests, request.correlation, entry)}
  end

  @spec next(t(), map()) :: {:ok, round(), t()} | {:error, :unknown_request}
  def next(%__MODULE__{} = tracker, correlation) when is_map(correlation) do
    case Map.fetch(tracker.requests, correlation) do
      {:ok, entry} ->
        round = %{
          attempt_id: attempt_id(entry.command_id, entry.next_round),
          tool_call_id: entry.tool_call_id
        }

        entry = %{entry | next_round: entry.next_round + 1}
        {:ok, round, %{tracker | requests: Map.put(tracker.requests, correlation, entry)}}

      :error ->
        {:error, :unknown_request}
    end
  end

  @spec complete(t(), map()) :: t()
  def complete(%__MODULE__{} = tracker, correlation) when is_map(correlation) do
    %{tracker | requests: Map.delete(tracker.requests, correlation)}
  end

  defp tool_call_id(%ActiveRequest{kind: {:completion, continuation}}),
    do: continuation.invocation_id

  defp tool_call_id(%ActiveRequest{}), do: nil

  defp attempt_id(command_id, round) do
    digest = :crypto.hash(:sha256, command_id <> ":model:" <> Integer.to_string(round))
    "matt_" <> Base.url_encode64(digest, padding: false)
  end
end
