defmodule Vxpipe.AgentRuntime.ModelContextCompactor do
  @moduledoc "Runs a summary-only request through the activation's pinned model provider."

  @behaviour Vxpipe.AgentRuntime.ContextCompactor

  alias Vxpipe.AgentRuntime.{
    CompactionObservation,
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
         {:ok, %ModelResponse{} = response} <- model_provider.generate(model, model_request) do
      normalize_response(response)
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

  defp normalize_response(%ModelResponse{tool_calls: []} = response) do
    case CompactionResult.new(
           summary: response.text,
           usage: response.usage,
           provider_metadata: response.provider_metadata
         ) do
      {:ok, result} -> {:ok, result}
      {:error, :invalid_compaction_result} -> observed_failure(response)
    end
  end

  defp normalize_response(%ModelResponse{} = response), do: observed_failure(response)

  defp observed_failure(%ModelResponse{} = response) do
    case CompactionObservation.new(
           usage: response.usage,
           provider_metadata: response.provider_metadata,
           outcome: :failed
         ) do
      {:ok, observation} ->
        {:error, :context_compaction_unavailable, observation}

      {:error, :invalid_compaction_observation} ->
        {:error, :context_compaction_unavailable}
    end
  end
end
