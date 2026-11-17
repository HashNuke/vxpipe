defmodule Vxpipe.AgentRuntime.ModelContextCompactor do
  @moduledoc "Runs a summary-only request through the activation's pinned model provider."

  @behaviour Vxpipe.AgentRuntime.ContextCompactor

  alias Vxpipe.AgentRuntime.{
    CompactionObservation,
    CompactionProjection,
    CompactionRequest,
    CompactionResult,
    ModelRequest,
    ModelResponse,
    Prompt
  }

  @spec new(module(), term(), keyword()) :: {:ok, map()} | {:error, :prompt_unavailable}
  def new(model_provider, model, options \\ []) do
    directory =
      Keyword.get(
        options,
        :prompt_directory,
        Application.app_dir(:vxpipe_agent_runtime, "priv/prompts")
      )

    with {:ok, prompt} <- Prompt.load(:conversation_summary, directory) do
      {:ok, %{model_provider: model_provider, model: model, summary_prompt: prompt}}
    end
  end

  @doc false
  @spec pin(map()) :: {:ok, map()} | {:error, :prompt_unavailable}
  def pin(%{model_provider: _provider, model: _model, summary_prompt: %Prompt{}} = config),
    do: {:ok, config}

  def pin(%{summary_prompt: _invalid}), do: {:error, :prompt_unavailable}

  def pin(%{model_provider: provider, model: model} = config) do
    with {:ok, pinned} <- new(provider, model), do: {:ok, Map.merge(config, pinned)}
  end

  def pin(_config), do: {:error, :prompt_unavailable}

  @doc false
  @spec pin(map(), Prompt.t() | nil) :: {:ok, map()} | {:error, :prompt_unavailable}
  def pin(config, nil), do: pin(config)

  def pin(
        %{model_provider: _provider, model: _model, summary_prompt: %Prompt{}} = config,
        %Prompt{} = prompt
      ),
      do: {:ok, Map.put(config, :summary_prompt, prompt)}

  def pin(%{summary_prompt: _invalid}, %Prompt{}), do: {:error, :prompt_unavailable}

  def pin(%{model_provider: _provider, model: _model} = config, %Prompt{} = prompt),
    do: {:ok, Map.put(config, :summary_prompt, prompt)}

  def pin(_config, _prompt), do: {:error, :prompt_unavailable}

  @impl true
  def compact(
        %{model_provider: model_provider, model: model, summary_prompt: %Prompt{} = prompt},
        %CompactionRequest{} = request
      )
      when is_atom(model_provider) do
    model_request =
      request.messages
      |> CompactionProjection.messages(prompt.text)
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

  def compact(%{model_provider: provider, model: model}, %CompactionRequest{} = request) do
    with {:ok, config} <- new(provider, model), do: compact(config, request)
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
