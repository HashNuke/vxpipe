defmodule Vxpipe.AgentRuntime.CompactionRunner do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{CompactionObservation, CompactionRequest, CompactionResult}

  @type compactor :: {module(), term()}

  @spec run(compactor(), CompactionRequest.t(), pos_integer()) ::
          {:ok, CompactionResult.t()}
          | {:error, :context_compaction_unavailable}
          | {:error, :context_compaction_unavailable, CompactionObservation.t()}
  def run({module, state}, %CompactionRequest{} = request, timeout_ms)
      when is_atom(module) and is_integer(timeout_ms) and timeout_ms > 0 do
    task = Task.async(fn -> invoke(module, state, request) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %CompactionResult{} = result}} ->
        {:ok, result}

      {:ok, {:error, _reason, %CompactionObservation{} = observation}} ->
        {:error, :context_compaction_unavailable, observation}

      _unavailable ->
        {:error, :context_compaction_unavailable}
    end
  end

  def run(_compactor, %CompactionRequest{}, _timeout_ms),
    do: {:error, :context_compaction_unavailable}

  defp invoke(module, state, request) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :compact, 2) do
      case module.compact(state, request) do
        {:ok, %CompactionResult{} = result} ->
          {:ok, result}

        {:error, reason, %CompactionObservation{} = observation} ->
          {:error, reason, observation}

        _invalid ->
          {:error, :context_compaction_unavailable}
      end
    else
      _invalid -> {:error, :context_compaction_unavailable}
    end
  rescue
    _error -> {:error, :context_compaction_unavailable}
  catch
    _kind, _reason -> {:error, :context_compaction_unavailable}
  end
end
