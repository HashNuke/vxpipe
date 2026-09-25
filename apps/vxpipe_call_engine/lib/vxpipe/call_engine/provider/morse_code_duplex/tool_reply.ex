defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.ToolReply do
  @moduledoc """
  Detects caller tool triggers and turns a delegated tool result into a
  Morse-encodable spoken reply.
  """

  @reply_prefix "RECEIVED "

  @spec trigger(String.t()) :: {:tool, String.t(), map()} | :not_a_tool
  def trigger(text) do
    case parse(text) do
      {:tool, _name, _arguments} = tool -> tool
      :not_a_tool -> :not_a_tool
    end
  end

  @spec text(map(), term()) :: {:ok, String.t()} | {:error, :empty_tool_reply}
  def text(config, result) do
    text =
      result
      |> summarize()
      |> morse_safe()
      |> String.slice(0, truncate_limit(config))

    if text == "", do: {:error, :empty_tool_reply}, else: {:ok, @reply_prefix <> text}
  end

  @spec reply(map(), String.t()) :: String.t()
  def reply(config, text), do: @reply_prefix <> String.slice(text, 0, truncate_limit(config))

  defp parse(text) when is_binary(text) do
    case String.split(String.trim(text), ~r/\s+/, parts: 3) do
      [keyword, name, encoded] when byte_size(name) in 1..256 ->
        if String.upcase(keyword) == "TOOL" and String.valid?(name) do
          decode(name, encoded)
        else
          :not_a_tool
        end

      _other ->
        :not_a_tool
    end
  rescue
    _exception -> :not_a_tool
  end

  defp parse(_text), do: :not_a_tool

  defp decode(name, encoded) do
    case JSON.decode(encoded) do
      {:ok, arguments} ->
        if Vxpipe.CallEngine.Speech.ToolArguments.valid?(arguments),
          do: {:tool, name, arguments},
          else: :not_a_tool

      {:error, _reason} ->
        :not_a_tool
    end
  end

  defp summarize(result) when is_binary(result), do: result
  defp summarize(result), do: inspect(result)

  # Morse's alphabet is limited; keep only characters the encoder can carry.
  defp morse_safe(text) do
    text
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9 ]+/, " ")
    |> String.replace(~r/ +/, " ")
    |> String.trim()
  end

  defp truncate_limit(config), do: max(config.maximum_text_bytes - byte_size(@reply_prefix), 0)
end
