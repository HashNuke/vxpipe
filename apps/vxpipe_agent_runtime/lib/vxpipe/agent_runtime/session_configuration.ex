defmodule Vxpipe.AgentRuntime.SessionConfiguration do
  @moduledoc false

  alias Vxpipe.AgentRuntime.ToolRegistry

  @derive {Inspect, only: []}
  @enforce_keys [
    :instructions,
    :model_provider,
    :model,
    :tool_registry,
    :executor,
    :maximum_model_rounds,
    :maximum_tool_calls_per_round,
    :maximum_output_bytes,
    :maximum_stream_events_per_round,
    :event_handoff_timeout_ms,
    :pending_context_source,
    :pending_context_timeout_ms,
    :maximum_pending_invocations,
    :commit_timeout_ms,
    :request_timeout_ms,
    :event_destination
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options) when is_list(options) do
    with {:ok, options} <- validate_options(options),
         instructions when is_binary(instructions) <- Keyword.get(options, :instructions),
         {:ok, model_provider} <- validate_provider(Keyword.get(options, :model_provider)),
         {:ok, tool_registry} <- ToolRegistry.new(Keyword.get(options, :tools, [])),
         {:ok, executor} <- validate_executor(Keyword.get(options, :executor), tool_registry),
         {:ok, maximum_model_rounds} <-
           positive(Keyword.get(options, :maximum_model_rounds, 8)),
         {:ok, maximum_tool_calls_per_round} <-
           positive(Keyword.get(options, :maximum_tool_calls_per_round, 32)),
         {:ok, maximum_output_bytes} <-
           positive(Keyword.get(options, :maximum_output_bytes, 256 * 1_024)),
         {:ok, maximum_stream_events_per_round} <-
           positive(Keyword.get(options, :maximum_stream_events_per_round, 4_096)),
         {:ok, event_handoff_timeout_ms} <-
           positive(Keyword.get(options, :event_handoff_timeout_ms, 1_000)),
         {:ok, pending_context_source} <-
           validate_pending_context_source(Keyword.get(options, :pending_context_source)),
         {:ok, pending_context_timeout_ms} <-
           positive(Keyword.get(options, :pending_context_timeout_ms, 1_000)),
         {:ok, maximum_pending_invocations} <-
           positive(Keyword.get(options, :maximum_pending_invocations, 32)),
         {:ok, commit_timeout_ms} <- positive(Keyword.get(options, :commit_timeout_ms, 1_000)),
         {:ok, request_timeout_ms} <-
           positive(Keyword.get(options, :request_timeout_ms, 30_000)),
         {:ok, event_destination} <-
           resolve_event_destination(Keyword.get(options, :event_destination)) do
      {:ok,
       %__MODULE__{
         instructions: instructions,
         model_provider: model_provider,
         model: Keyword.get(options, :model),
         tool_registry: tool_registry,
         executor: executor,
         maximum_model_rounds: maximum_model_rounds,
         maximum_tool_calls_per_round: maximum_tool_calls_per_round,
         maximum_output_bytes: maximum_output_bytes,
         maximum_stream_events_per_round: maximum_stream_events_per_round,
         event_handoff_timeout_ms: event_handoff_timeout_ms,
         pending_context_source: pending_context_source,
         pending_context_timeout_ms: pending_context_timeout_ms,
         maximum_pending_invocations: maximum_pending_invocations,
         commit_timeout_ms: commit_timeout_ms,
         request_timeout_ms: request_timeout_ms,
         event_destination: event_destination
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  @spec runner_options(t(), map()) :: map()
  def runner_options(
        %__MODULE__{} = config,
        %{
          begin_submission: begin_submission,
          commit: commit,
          emit_model_usage: emit_model_usage,
          emit_text_delta: emit_text_delta
        }
      )
      when is_function(begin_submission, 0) and is_function(commit, 1) and
             is_function(emit_model_usage, 2) and is_function(emit_text_delta, 1) do
    %{
      model_provider: config.model_provider,
      model: config.model,
      tool_registry: config.tool_registry,
      executor: config.executor,
      maximum_model_rounds: config.maximum_model_rounds,
      maximum_tool_calls_per_round: config.maximum_tool_calls_per_round,
      maximum_output_bytes: config.maximum_output_bytes,
      maximum_stream_events_per_round: config.maximum_stream_events_per_round,
      pending_context_source: config.pending_context_source,
      pending_context_timeout_ms: config.pending_context_timeout_ms,
      maximum_pending_invocations: config.maximum_pending_invocations,
      begin_submission: begin_submission,
      commit: commit,
      emit_model_usage: emit_model_usage,
      emit_text_delta: emit_text_delta
    }
  end

  defp validate_options(options) do
    Keyword.validate(options, [
      :instructions,
      :model_provider,
      :model,
      :tools,
      :executor,
      :maximum_model_rounds,
      :maximum_tool_calls_per_round,
      :maximum_output_bytes,
      :maximum_stream_events_per_round,
      :event_handoff_timeout_ms,
      :pending_context_source,
      :pending_context_timeout_ms,
      :maximum_pending_invocations,
      :commit_timeout_ms,
      :request_timeout_ms,
      :event_destination
    ])
  end

  defp validate_provider(model_provider) when is_atom(model_provider) do
    if Code.ensure_loaded?(model_provider) and function_exported?(model_provider, :generate, 2) do
      {:ok, model_provider}
    else
      {:error, :invalid_provider}
    end
  end

  defp validate_provider(_model_provider), do: {:error, :invalid_provider}

  defp validate_executor(nil, %ToolRegistry{size: 0}), do: {:ok, nil}

  defp validate_executor(executor, %ToolRegistry{}) when is_atom(executor) do
    if Code.ensure_loaded?(executor) and function_exported?(executor, :submit, 4) do
      {:ok, executor}
    else
      {:error, :invalid_executor}
    end
  end

  defp validate_executor(_executor, _tool_registry), do: {:error, :invalid_executor}

  defp validate_pending_context_source({module, _source} = context_source)
       when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :snapshot, 3) do
      {:ok, context_source}
    else
      {:error, :invalid_pending_context_source}
    end
  end

  defp validate_pending_context_source(_context_source),
    do: {:error, :invalid_pending_context_source}

  defp resolve_event_destination(destination) do
    case GenServer.whereis(destination) do
      pid when is_pid(pid) -> {:ok, pid}
      _missing -> {:error, :invalid_event_destination}
    end
  rescue
    _exception -> {:error, :invalid_event_destination}
  end

  defp positive(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(_value), do: {:error, :invalid_limit}
end
