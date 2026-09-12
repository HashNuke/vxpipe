defmodule Vxpipe.AgentRuntime.CompactionRunner do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{CompactionRequest, CompactionResult}

  @type compactor :: {module(), term()}

  @spec run(compactor(), CompactionRequest.t(), pos_integer()) ::
          {:ok, CompactionResult.t()} | {:error, :context_compaction_unavailable}
  def run({module, state}, %CompactionRequest{} = request, timeout_ms)
      when is_atom(module) and is_integer(timeout_ms) and timeout_ms > 0 do
    task = Task.async(fn -> invoke(module, state, request) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %CompactionResult{} = result}} -> {:ok, result}
      _unavailable -> {:error, :context_compaction_unavailable}
    end
  end

  def run(_compactor, %CompactionRequest{}, _timeout_ms),
    do: {:error, :context_compaction_unavailable}

  defp invoke(module, state, request) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :compact, 2),
         {:ok, %CompactionResult{} = result} <- module.compact(state, request) do
      {:ok, result}
    else
      _invalid -> {:error, :context_compaction_unavailable}
    end
  rescue
    _error -> {:error, :context_compaction_unavailable}
  catch
    _kind, _reason -> {:error, :context_compaction_unavailable}
  end
end
