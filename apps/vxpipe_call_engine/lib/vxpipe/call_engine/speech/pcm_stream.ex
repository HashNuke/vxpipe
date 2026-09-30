defmodule Vxpipe.CallEngine.Speech.PCMStream do
  @moduledoc "Bounded raw signed 16-bit PCM framing across transport fragments."
  defstruct bytes: 0, carry: <<>>, maximum_bytes: 33_554_432
  @chunk_bytes 65_536

  def new(maximum_bytes \\ 33_554_432) when is_integer(maximum_bytes) and maximum_bytes > 0,
    do: %__MODULE__{maximum_bytes: maximum_bytes}

  def feed(%__MODULE__{} = state, chunk) when is_binary(chunk) do
    bytes = state.bytes + byte_size(chunk)

    if bytes <= state.maximum_bytes do
      combined = state.carry <> chunk
      size = byte_size(combined) - rem(byte_size(combined), 2)
      <<audio::binary-size(size), carry::binary>> = combined
      {:ok, %{state | bytes: bytes, carry: carry}, chunks(audio)}
    else
      {:error, :invalid_audio}
    end
  end

  def finish(%__MODULE__{bytes: bytes, carry: <<>>}) when bytes > 0, do: :ok
  def finish(%__MODULE__{}), do: {:error, :invalid_audio}

  defp chunks(<<>>), do: []
  defp chunks(audio) when byte_size(audio) <= @chunk_bytes, do: [audio]
  defp chunks(<<audio::binary-size(@chunk_bytes), rest::binary>>), do: [audio | chunks(rest)]
end
