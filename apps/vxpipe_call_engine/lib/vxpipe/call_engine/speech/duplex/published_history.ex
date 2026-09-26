defmodule Vxpipe.CallEngine.Speech.Duplex.PublishedHistory do
  @moduledoc "Bounded published text for duplex session reseeding."

  @maximum_messages 128
  @maximum_tokens 8_192

  @derive {Inspect, only: [:tokens]}
  defstruct entries: [], tokens: 0

  def new, do: %__MODULE__{}

  def append(%__MODULE__{} = state, {role, text})
      when role in [:caller, :agent] and is_binary(text) and byte_size(text) > 0 do
    if String.valid?(text) do
      size = div(byte_size(text) + 3, 4)

      state = %{
        state
        | entries: state.entries ++ [{role, text, size}],
          tokens: state.tokens + size
      }

      trim(state)
    else
      state
    end
  end

  def append(%__MODULE__{} = state, _entry), do: state

  def input(%__MODULE__{} = state) do
    Enum.map(state.entries, fn {role, text, _tokens} ->
      %{
        "type" => "message",
        "role" => if(role == :caller, do: "user", else: "assistant"),
        "content" => [%{"type" => "input_text", "text" => text}]
      }
    end)
  end

  def tokens(%__MODULE__{} = state), do: state.tokens

  defp trim(%__MODULE__{entries: [_oldest | rest], tokens: tokens} = state)
       when length(state.entries) > @maximum_messages or tokens > @maximum_tokens do
    {_role, _text, size} = hd(state.entries)
    trim(%{state | entries: rest, tokens: tokens - size})
  end

  defp trim(state), do: state
end
