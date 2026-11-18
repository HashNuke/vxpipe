defmodule Vxpipe.AgentRuntime.SessionConfiguration do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{CompactionConfiguration, DialogueRepair, Message, ToolRegistry}

  @derive {Inspect, only: []}
  @enforce_keys [
    :instructions,
    :history_mode,
    :reply_protocol,
    :reply_repair_policy,
    :initial_messages,
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
    :model_context_source,
    :model_context_timeout_ms,
    :maximum_model_context_bytes,
    :context_preparation,
    :commit_timeout_ms,
    :request_timeout_ms,
    :event_destination
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @doc false
  @spec pin_compaction(keyword()) :: {:ok, keyword()} | {:error, atom()}
  def pin_compaction(options) do
    with {:ok, preparation} <-
           CompactionConfiguration.new(
             Keyword.get(options, :model_provider),
             Keyword.get(options, :model),
             Keyword.get(options, :context_compaction)
           ) do
      options =
        case preparation do
          nil ->
            options

          %{compactor: compactor} ->
            compaction =
              options |> Keyword.fetch!(:context_compaction) |> Keyword.put(:compactor, compactor)

            Keyword.put(options, :context_compaction, compaction)
        end

      {:ok,
       Keyword.put_new_lazy(options, :reply_repair_policy, fn ->
         DialogueRepair.pin(
           Keyword.get(options, :reply_protocol, :legacy),
           Keyword.get(options, :model_provider),
           Keyword.get(options, :model),
           preparation
         )
       end)}
    end
  end

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options) when is_list(options) do
    with {:ok, options} <- validate_options(options),
         instructions when is_binary(instructions) <- Keyword.get(options, :instructions),
         history_mode when history_mode in [:generated, :host_settled] <-
           Keyword.get(options, :history_mode, :generated),
         {:ok, initial_messages} <-
           validate_initial_messages(
             Keyword.get(options, :initial_messages, []),
             Keyword.get(options, :maximum_output_bytes, 256 * 1_024)
           ),
         {:ok, model_provider} <- validate_provider(Keyword.get(options, :model_provider)),
         {:ok, tool_registry} <- ToolRegistry.new(Keyword.get(options, :tools, [])),
         {:ok, reply_protocol} <-
           validate_reply_protocol(options, model_provider, tool_registry, history_mode),
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
         {:ok, model_context_source} <-
           validate_model_context_source(Keyword.get(options, :model_context_source)),
         {:ok, model_context_timeout_ms} <-
           positive(Keyword.get(options, :model_context_timeout_ms, 1_000)),
         {:ok, maximum_model_context_bytes} <-
           positive(Keyword.get(options, :maximum_model_context_bytes, 256 * 1_024)),
         {:ok, context_preparation} <-
           CompactionConfiguration.new(
             model_provider,
             Keyword.get(options, :model),
             Keyword.get(options, :context_compaction)
           ),
         reply_repair_policy =
           Keyword.get_lazy(options, :reply_repair_policy, fn ->
             DialogueRepair.pin(
               reply_protocol,
               model_provider,
               Keyword.get(options, :model),
               context_preparation
             )
           end),
         true <- DialogueRepair.valid?(reply_repair_policy, reply_protocol),
         {:ok, commit_timeout_ms} <- positive(Keyword.get(options, :commit_timeout_ms, 1_000)),
         {:ok, request_timeout_ms} <-
           positive(Keyword.get(options, :request_timeout_ms, 30_000)),
         {:ok, event_destination} <-
           resolve_event_destination(Keyword.get(options, :event_destination)) do
      {:ok,
       %__MODULE__{
         instructions: instructions,
         history_mode: history_mode,
         reply_protocol: reply_protocol,
         reply_repair_policy: reply_repair_policy,
         initial_messages: initial_messages,
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
         model_context_source: model_context_source,
         model_context_timeout_ms: model_context_timeout_ms,
         maximum_model_context_bytes: maximum_model_context_bytes,
         context_preparation: context_preparation,
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
          emit_context_compaction_usage: emit_context_compaction_usage,
          emit_model_attempt_started: emit_model_attempt_started,
          emit_model_usage: emit_model_usage,
          emit_text_delta: emit_text_delta
        }
      )
      when is_function(begin_submission, 0) and is_function(commit, 1) and
             is_function(emit_context_compaction_usage, 3) and
             is_function(emit_model_attempt_started, 0) and is_function(emit_model_usage, 2) and
             is_function(emit_text_delta, 1) do
    %{
      model_provider: config.model_provider,
      history_mode: config.history_mode,
      reply_protocol: config.reply_protocol,
      reply_repair_policy: config.reply_repair_policy,
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
      model_context_source: config.model_context_source,
      model_context_timeout_ms: config.model_context_timeout_ms,
      maximum_model_context_bytes: config.maximum_model_context_bytes,
      context_preparation: prepared_compaction(config),
      begin_submission: begin_submission,
      commit: commit,
      emit_context_compaction_usage: emit_context_compaction_usage,
      emit_model_attempt_started: emit_model_attempt_started,
      emit_model_usage: emit_model_usage,
      emit_text_delta: emit_text_delta
    }
  end

  defp validate_options(options) do
    Keyword.validate(options, [
      :instructions,
      :history_mode,
      :reply_protocol,
      :reply_repair_policy,
      :initial_messages,
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
      :model_context_source,
      :model_context_timeout_ms,
      :maximum_model_context_bytes,
      :context_compaction,
      :commit_timeout_ms,
      :request_timeout_ms,
      :event_destination
    ])
  end

  defp prepared_compaction(%__MODULE__{context_preparation: nil}), do: nil

  defp prepared_compaction(%__MODULE__{} = config) do
    format = if config.history_mode == :host_settled, do: :structured, else: :legacy
    Map.put(config.context_preparation, :summary_format, format)
  end

  defp validate_provider(model_provider) when is_atom(model_provider) do
    if Code.ensure_loaded?(model_provider) and function_exported?(model_provider, :generate, 2) do
      {:ok, model_provider}
    else
      {:error, :invalid_provider}
    end
  end

  defp validate_provider(_model_provider), do: {:error, :invalid_provider}

  defp validate_reply_protocol(options, provider, registry, history_mode) do
    case Keyword.get(options, :reply_protocol, :legacy) do
      :legacy ->
        {:ok, :legacy}

      :mode_message_v1 when history_mode == :host_settled ->
        if function_exported?(provider, :supports_protocol?, 3) and
             provider.supports_protocol?(
               Keyword.get(options, :model),
               :mode_message_v1,
               ToolRegistry.model_tools(registry)
             ) do
          {:ok, :mode_message_v1}
        else
          {:error, :unsupported_reply_protocol}
        end

      _invalid ->
        {:error, :unsupported_reply_protocol}
    end
  end

  defp validate_initial_messages(messages, maximum_output_bytes)
       when is_list(messages) and is_integer(maximum_output_bytes) and maximum_output_bytes > 0 do
    if Enum.all?(messages, &valid_initial_message?(&1, maximum_output_bytes)) do
      {:ok, messages}
    else
      {:error, :invalid_initial_messages}
    end
  end

  defp validate_initial_messages(_messages, _maximum), do: {:error, :invalid_initial_messages}

  defp valid_initial_message?(
         %Message{
           role: :user,
           content: content,
           origin: :caller,
           name: nil,
           tool_call_id: nil,
           tool_calls: [],
           provider_replay: replay
         },
         _maximum
       )
       when replay == %{},
       do: valid_initial_content?(content)

  defp valid_initial_message?(
         %Message{
           role: :assistant,
           content: content,
           origin: nil,
           name: nil,
           tool_call_id: nil,
           tool_calls: [],
           provider_replay: replay
         } = message,
         maximum
       )
       when replay == %{},
       do: valid_initial_content?(content) or Message.valid_spoken?(message, maximum)

  defp valid_initial_message?(_message, _maximum), do: false

  defp valid_initial_content?(content) when is_binary(content) do
    content != "" and byte_size(content) <= 64 * 1_024
  end

  defp valid_initial_content?(_content), do: false

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

  defp validate_model_context_source(nil), do: {:ok, nil}

  defp validate_model_context_source({module, _source} = context_source) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :snapshot, 3) do
      {:ok, context_source}
    else
      {:error, :invalid_model_context_source}
    end
  end

  defp validate_model_context_source(_context_source),
    do: {:error, :invalid_model_context_source}

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
