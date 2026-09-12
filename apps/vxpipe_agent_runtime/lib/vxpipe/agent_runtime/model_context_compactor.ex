defmodule Vxpipe.AgentRuntime.ModelContextCompactor do
  @moduledoc "Runs a summary-only request through the activation's pinned model provider."

  @behaviour Vxpipe.AgentRuntime.ContextCompactor

  alias Vxpipe.AgentRuntime.{
    CompactionProjection,
    CompactionRequest,
    CompactionResult,
    ModelRequest,
    ModelResponse
  }

  @impl true
  def compact(
        %{model_provider: model_provider, model: model},
        %CompactionRequest{} = request
      )
      when is_atom(model_provider) do
    model_request =
      request.messages
      |> CompactionProjection.messages()
      |> ModelRequest.new([], [], %{}, request.correlation)
      |> ModelRequest.with_maximum_output_tokens(request.maximum_summary_tokens)

    with true <- Code.ensure_loaded?(model_provider),
         true <- function_exported?(model_provider, :generate, 2),
         {:ok, %ModelResponse{tool_calls: []} = response} <-
           model_provider.generate(model, model_request),
         {:ok, result} <-
           CompactionResult.new(
             summary: response.text,
             usage: response.usage,
             provider_metadata: response.provider_metadata
           ) do
      {:ok, result}
    else
      _invalid -> {:error, :context_compaction_unavailable}
    end
  rescue
    _error -> {:error, :context_compaction_unavailable}
  catch
    _kind, _reason -> {:error, :context_compaction_unavailable}
  end

  def compact(_state, %CompactionRequest{}),
    do: {:error, :context_compaction_unavailable}
end
