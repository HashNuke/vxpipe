defmodule Vxpipe.CallEngine.Capability.SentenceAccumulator do
  @moduledoc false

  defstruct [:maximum_bytes, buffer: "", byte_count: 0, segments: []]

  @type t :: %__MODULE__{
          maximum_bytes: pos_integer(),
          buffer: String.t(),
          byte_count: non_neg_integer(),
          segments: [String.t()]
        }

  @spec new(pos_integer()) :: t()
  def new(maximum_bytes), do: %__MODULE__{maximum_bytes: maximum_bytes}

  @spec push(t(), term()) :: {:ok, t(), [String.t()]} | {:error, :invalid_response}
  def push(%__MODULE__{} = accumulator, chunk) when is_binary(chunk) do
    byte_count = accumulator.byte_count + byte_size(chunk)

    if String.valid?(chunk) and byte_count <= accumulator.maximum_bytes do
      {segments, buffer} = take_sentences(accumulator.buffer <> chunk, [])

      {:ok,
       %{
         accumulator
         | buffer: buffer,
           byte_count: byte_count,
           segments: accumulator.segments ++ segments
       }, segments}
    else
      {:error, :invalid_response}
    end
  end

  def push(%__MODULE__{}, _chunk), do: {:error, :invalid_response}

  @spec finish(t()) :: {:ok, [String.t()], String.t()} | {:error, :invalid_response}
  def finish(%__MODULE__{} = accumulator) do
    tail = String.trim(accumulator.buffer)
    pending = if tail == "", do: [], else: [tail]
    segments = accumulator.segments ++ pending

    case String.trim(Enum.join(segments, " ")) do
      "" -> {:error, :invalid_response}
      text -> {:ok, pending, text}
    end
  end

  defp take_sentences(buffer, sentences) do
    case Regex.run(~r/\A(.*?[.!?])(?=\s+)/us, buffer, capture: :all_but_first) do
      [sentence] ->
        rest =
          buffer
          |> binary_part(byte_size(sentence), byte_size(buffer) - byte_size(sentence))
          |> String.trim_leading()

        take_sentences(rest, [String.trim(sentence) | sentences])

      nil ->
        {Enum.reverse(sentences), buffer}
    end
  end
end
