defmodule Vxpipe.AgentRuntime.ModelResponse do
  @moduledoc "A bounded, normalized model response."

  alias Vxpipe.AgentRuntime.ToolCall

  @derive {Inspect, only: []}
  @enforce_keys [:text, :tool_calls]
  defstruct @enforce_keys

  @type t :: %__MODULE__{text: String.t(), tool_calls: [ToolCall.t()]}

  @maximum_text_bytes 256 * 1_024
  @maximum_tool_calls 32

  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attributes) when is_list(attributes) do
    with {:ok, attributes} <- Keyword.validate(attributes, [:text, tool_calls: []]),
         {:ok, text} <- validate_text(Keyword.get(attributes, :text)),
         {:ok, tool_calls} <- validate_tool_calls(Keyword.fetch!(attributes, :tool_calls)),
         false <- text == "" and tool_calls == [] do
      {:ok, %__MODULE__{text: text, tool_calls: tool_calls}}
    else
      true -> {:error, :empty_response}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_response}
    end
  end

  def new(_attributes), do: {:error, :invalid_response}

  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{text: text, tool_calls: tool_calls}) do
    with {:ok, _text} <- validate_text(text),
         {:ok, _tool_calls} <- validate_tool_calls(tool_calls) do
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
end
