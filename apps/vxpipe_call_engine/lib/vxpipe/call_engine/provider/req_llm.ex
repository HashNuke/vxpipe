defmodule Vxpipe.CallEngine.Provider.ReqLLM do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.ModelInference

  alias Elixir.ReqLLM.Context
  alias Elixir.ReqLLM.Response
  alias Elixir.ReqLLM.StreamResponse
  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.Provider.ReqLLM.Config
  alias Vxpipe.CallEngine.Tool.{Call, Definition}

  @impl true
  def new(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             api_key: nil,
             model: nil,
             generation_options: [],
             streaming: :auto
           ),
         api_key when is_binary(api_key) <- Keyword.fetch!(options, :api_key),
         true <- String.trim(api_key) != "",
         model_spec when is_binary(model_spec) <- Keyword.fetch!(options, :model),
         true <- String.trim(model_spec) != "",
         generation_options when is_list(generation_options) <-
           Keyword.fetch!(options, :generation_options),
         true <- Keyword.keyword?(generation_options),
         streaming when streaming in [:auto, true, false] <- Keyword.fetch!(options, :streaming),
         false <- Keyword.has_key?(generation_options, :api_key),
         false <- Keyword.has_key?(generation_options, :tools),
         {:ok, model} <- Elixir.ReqLLM.model(model_spec) do
      {:ok,
       %Config{
         api_key: api_key,
         model: model,
         generation_options: generation_options,
         streaming: resolve_streaming(streaming, model)
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  @impl true
  def streaming?(%Config{} = config), do: config.streaming

  @impl true
  def stream(%Config{} = config, messages, definitions, emit) when is_list(messages) do
    {model, context, options} = prepare_request(config, messages, definitions)

    case Elixir.ReqLLM.stream_text(model, context, options) do
      {:ok, %StreamResponse{} = response} ->
        try do
          case StreamResponse.process_stream(response, on_result: &emit_chunk(&1, emit)) do
            {:ok, %Response{} = response} -> classify_stream_response(response)
            {:error, _reason} -> {:error, :provider_unavailable}
          end
        rescue
          _exception -> {:error, :provider_unavailable}
        catch
          {:vxpipe_emit_failed, reason} -> {:error, reason}
        end

      {:error, _reason} ->
        {:error, :provider_unavailable}
    end
  end

  @impl true
  def generate(%Config{} = config, messages, definitions) when is_list(messages) do
    {model, context, options} = prepare_request(config, messages, definitions)

    case Elixir.ReqLLM.generate_text(model, context, options) do
      {:ok, %Response{} = response} ->
        classify_response(response)

      {:error, _reason} ->
        {:error, :provider_unavailable}
    end
  end

  @doc false
  def prepare_request(%Config{} = config, messages) when is_list(messages) do
    prepare_request(config, messages, [])
  end

  @doc false
  def prepare_request(%Config{} = config, messages, definitions) when is_list(messages) do
    context =
      messages
      |> Enum.map(&to_req_llm_message/1)
      |> Context.new()

    options =
      config.generation_options
      |> Keyword.put(:api_key, config.api_key)
      |> put_tools(definitions)

    {config.model, context, options}
  end

  defp to_req_llm_message(%Message{role: :system, content: content}),
    do: Context.system(content)

  defp to_req_llm_message(%Message{role: :user, content: content}),
    do: Context.user(content)

  defp to_req_llm_message(%Message{role: :assistant, content: content, tool_calls: calls}) do
    tool_calls =
      Enum.map(calls, fn call ->
        Elixir.ReqLLM.ToolCall.new(call.id, call.name, JSON.encode!(call.arguments))
      end)

    Context.assistant(content, tool_calls: tool_calls)
  end

  defp to_req_llm_message(%Message{
         role: :tool,
         content: content,
         name: name,
         tool_call_id: tool_call_id
       }) do
    Context.tool_result(tool_call_id, name, content)
  end

  defp put_tools(options, []), do: options

  defp put_tools(options, definitions) do
    tools = Enum.map(definitions, &to_req_llm_tool/1)
    Keyword.put(options, :tools, tools)
  end

  defp to_req_llm_tool(%Definition{} = definition) do
    Elixir.ReqLLM.Tool.new!(
      name: definition.name,
      description: definition.description,
      parameter_schema: definition.parameters,
      callback: fn _arguments -> {:error, :engine_owned_tool} end
    )
  end

  defp emit_chunk(chunk, emit) do
    case emit.(chunk) do
      :ok -> :ok
      {:error, reason} -> throw({:vxpipe_emit_failed, reason})
    end
  end

  defp classify_response(response) do
    case Response.classify(response) do
      %{type: :final_answer, text: text} when is_binary(text) ->
        {:ok, text}

      %{type: :tool_calls, tool_calls: calls} when is_list(calls) ->
        normalize_tool_calls(calls)

      _invalid ->
        {:error, :invalid_response}
    end
  end

  defp classify_stream_response(response) do
    case classify_response(response) do
      {:ok, _text} -> :ok
      other -> other
    end
  end

  defp normalize_tool_calls(calls) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, normalized} ->
      case normalize_tool_call(call) do
        {:ok, call} -> {:cont, {:ok, [call | normalized]}}
        :error -> {:halt, {:error, :invalid_response}}
      end
    end)
    |> case do
      {:ok, normalized} when normalized != [] -> {:tool_calls, Enum.reverse(normalized)}
      _invalid -> {:error, :invalid_response}
    end
  end

  defp normalize_tool_call(%Elixir.ReqLLM.ToolCall{} = call) do
    normalize_tool_call(Elixir.ReqLLM.ToolCall.to_map(call))
  end

  defp normalize_tool_call(%{id: id, name: name, arguments: arguments})
       when is_binary(id) and id != "" and is_binary(name) and name != "" and is_map(arguments) do
    {:ok, %Call{id: id, name: name, arguments: arguments}}
  end

  defp normalize_tool_call(_call), do: :error

  defp resolve_streaming(:auto, model), do: Elixir.ReqLLM.ModelHelpers.streaming_text?(model)
  defp resolve_streaming(streaming, _model), do: streaming
end
