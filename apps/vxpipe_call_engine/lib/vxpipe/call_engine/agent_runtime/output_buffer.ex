defmodule Vxpipe.CallEngine.AgentRuntime.OutputBuffer do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SentenceAccumulator

  @derive {Inspect, only: [:byte_count]}
  @enforce_keys [:accumulator]
  defstruct @enforce_keys ++ [streamed_text: "", byte_count: 0]

  @type t :: %__MODULE__{
          accumulator: SentenceAccumulator.t(),
          streamed_text: String.t(),
          byte_count: non_neg_integer()
        }

  @spec new(pos_integer()) :: t()
  def new(maximum_bytes) when is_integer(maximum_bytes) and maximum_bytes > 0 do
    %__MODULE__{accumulator: SentenceAccumulator.new(maximum_bytes)}
  end

  @spec push(t(), String.t()) :: {:ok, t(), [String.t()]} | {:error, :invalid_response}
  def push(%__MODULE__{} = buffer, text) when is_binary(text) do
    case SentenceAccumulator.push(buffer.accumulator, text) do
      {:ok, accumulator, segments} ->
        {:ok,
         %{
           buffer
           | accumulator: accumulator,
             streamed_text: buffer.streamed_text <> text,
             byte_count: buffer.byte_count + byte_size(text)
         }, segments}

      {:error, :invalid_response} = error ->
        error
    end
  end

  @spec finish(t(), String.t()) :: {:ok, [String.t()]} | {:error, :invalid_response}
  def finish(%__MODULE__{} = buffer, complete_text) when is_binary(complete_text) do
    with {:ok, suffix} <- unstreamed_suffix(complete_text, buffer.streamed_text),
         {:ok, accumulator, segments} <- SentenceAccumulator.push(buffer.accumulator, suffix),
         {:ok, pending, _text} <- SentenceAccumulator.finish(accumulator) do
      {:ok, segments ++ pending}
    end
  end

  def finish(%__MODULE__{}, _complete_text), do: {:error, :invalid_response}

  defp unstreamed_suffix(text, ""), do: {:ok, text}

  defp unstreamed_suffix(text, streamed) do
    if String.starts_with?(text, streamed) do
      {:ok, binary_part(text, byte_size(streamed), byte_size(text) - byte_size(streamed))}
    else
      {:error, :invalid_response}
    end
  end
end
