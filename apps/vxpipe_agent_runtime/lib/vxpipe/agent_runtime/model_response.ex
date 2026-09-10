defmodule Vxpipe.AgentRuntime.ModelResponse do
  @moduledoc "A bounded, normalized model response."

  alias Vxpipe.AgentRuntime.ToolCall

  @derive {Inspect, only: []}
  @enforce_keys [:text, :tool_calls, :usage, :provider_metadata]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          text: String.t(),
          tool_calls: [ToolCall.t()],
          usage: map(),
          provider_metadata: map()
        }

  @maximum_text_bytes 256 * 1_024
  @maximum_tool_calls 32
  @maximum_usage_bytes 16 * 1_024
  @maximum_provider_metadata_bytes 64 * 1_024

  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <-
           Keyword.validate(attributes, [
             :text,
             tool_calls: [],
             usage: %{},
             provider_metadata: %{}
           ]),
         {:ok, text} <- validate_text(Keyword.get(attributes, :text)),
         {:ok, tool_calls} <- validate_tool_calls(Keyword.fetch!(attributes, :tool_calls)),
         {:ok, usage} <-
           validate_metadata(Keyword.fetch!(attributes, :usage), @maximum_usage_bytes),
         {:ok, provider_metadata} <-
           validate_metadata(
             Keyword.fetch!(attributes, :provider_metadata),
             @maximum_provider_metadata_bytes
           ),
         false <- text == "" and tool_calls == [] do
      {:ok,
       %__MODULE__{
         text: text,
         tool_calls: tool_calls,
         usage: usage,
         provider_metadata: provider_metadata
       }}
    else
      true -> {:error, :empty_response}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_response}
    end
  end

  def new(_attributes), do: {:error, :invalid_response}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{
        text: text,
        tool_calls: tool_calls,
        usage: usage,
        provider_metadata: provider_metadata
      }) do
    with {:ok, _text} <- validate_text(text),
         {:ok, _tool_calls} <- validate_tool_calls(tool_calls),
         {:ok, _usage} <- validate_metadata(usage, @maximum_usage_bytes),
         {:ok, _provider_metadata} <-
           validate_metadata(provider_metadata, @maximum_provider_metadata_bytes) do
      text != "" or tool_calls != []
    else
      _invalid -> false
    end
  end

  def valid?(_response), do: false

  defp validate_text(text)
       when is_binary(text) and byte_size(text) <= @maximum_text_bytes,
       do: {:ok, text}

  defp validate_text(text) when is_binary(text), do: {:error, :text_too_large}
  defp validate_text(_text), do: {:error, :invalid_response}

  defp validate_tool_calls(tool_calls) when is_list(tool_calls) do
    cond do
      length(tool_calls) > @maximum_tool_calls -> {:error, :too_many_tool_calls}
      Enum.all?(tool_calls, &ToolCall.valid?/1) -> {:ok, tool_calls}
      true -> {:error, :invalid_response}
    end
  end

  defp validate_tool_calls(_tool_calls), do: {:error, :invalid_response}

  defp validate_metadata(metadata, maximum_bytes) when is_map(metadata) do
    if :erlang.external_size(metadata) <= maximum_bytes do
      {:ok, metadata}
    else
      {:error, :metadata_too_large}
    end
  end

  defp validate_metadata(_metadata, _maximum_bytes), do: {:error, :invalid_response}
end
