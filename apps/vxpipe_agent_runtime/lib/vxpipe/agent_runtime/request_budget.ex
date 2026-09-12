defmodule Vxpipe.AgentRuntime.RequestBudget do
  @moduledoc "Measures a normalized model request and applies its context budget."

  alias Vxpipe.AgentRuntime.{ContextBudget, ModelRequest}

  @default_timeout_ms 1_000
  @task_supervisor Vxpipe.AgentRuntime.RequestSupervisor

  @type counter :: {module(), term()}

  @spec assess(ModelRequest.t(), ContextBudget.t(), counter(), keyword()) ::
          {:ok,
           %{
             decision: :within_budget | {:compact, non_neg_integer()},
             input_tokens: non_neg_integer()
           }}
          | {:error, :input_token_count_unavailable}
  def assess(request, budget, counter, options \\ [])

  def assess(%ModelRequest{} = request, %ContextBudget{} = budget, counter, options)
      when is_list(options) do
    with {:ok, timeout_ms} <- timeout(options),
         {:ok, input_tokens} <- count(counter, request, timeout_ms),
         {:ok, decision} <- ContextBudget.assess(budget, input_tokens) do
      {:ok, %{decision: decision, input_tokens: input_tokens}}
    else
      _unavailable -> {:error, :input_token_count_unavailable}
    end
  end

  def assess(_request, _budget, _counter, _options),
    do: {:error, :input_token_count_unavailable}

  defp count({module, state}, request, timeout_ms) when is_atom(module) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :count, 2) do
      task =
        Task.Supervisor.async_nolink(@task_supervisor, fn -> module.count(state, request) end)

      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, input_tokens}} when is_integer(input_tokens) and input_tokens >= 0 ->
          {:ok, input_tokens}

        _unavailable ->
          {:error, :input_token_count_unavailable}
      end
    else
      _invalid -> {:error, :input_token_count_unavailable}
    end
  rescue
    _error -> {:error, :input_token_count_unavailable}
  catch
    _kind, _reason -> {:error, :input_token_count_unavailable}
  end

  defp count(_counter, _request, _timeout_ms), do: {:error, :input_token_count_unavailable}

  defp timeout(options) do
    with {:ok, options} <- Keyword.validate(options, [:timeout_ms]),
         timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 <-
           Keyword.get(options, :timeout_ms, @default_timeout_ms) do
      {:ok, timeout_ms}
    else
      _invalid -> {:error, :invalid_timeout}
    end
  end
end
