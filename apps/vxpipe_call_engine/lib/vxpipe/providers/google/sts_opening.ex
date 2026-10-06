defmodule Vxpipe.Providers.Google.STSOpening do
  @moduledoc "Bounded fixed-opening verification before native Google output can reach playback."

  alias Vxpipe.CallEngine.Speech.Opening

  @maximum_chunks 4_096
  @output_chunk_bytes 131_072
  @maximum_audio_bytes 2_097_152

  def prepare(:generated),
    do:
      {:ok, "Begin the conversation now with an opening based on your system instructions.", nil}

  def prepare({:fixed, text} = opening) do
    if Opening.valid?(opening) do
      cue =
        "Begin the conversation by speaking exactly the following text, with no additions: " <>
          text

      {:ok, cue, %{expected: text, transcript: "", chunks: [], audio_bytes: 0}}
    else
      {:error, :invalid_opening}
    end
  end

  def prepare(_opening), do: {:error, :invalid_opening}

  def accept(opening, {:output_transcript, text}) do
    transcript = opening.transcript <> text

    if byte_size(transcript) <= byte_size(opening.expected),
      do: {:buffered, %{opening | transcript: transcript}},
      else: {:error, :text_mismatch}
  end

  def accept(opening, {:audio, pcm}) do
    bytes = opening.audio_bytes + byte_size(pcm)

    if byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0 and
         length(opening.chunks) < @maximum_chunks and bytes <= @maximum_audio_bytes do
      {:buffered, %{opening | chunks: opening.chunks ++ [pcm], audio_bytes: bytes}}
    else
      {:error, :audio_overflow}
    end
  end

  def accept(opening, :generation_complete) do
    if opening.transcript == opening.expected and opening.chunks != [] do
      events =
        [{:output_transcript, opening.transcript}] ++
          Enum.map(output_chunks(IO.iodata_to_binary(opening.chunks)), &{:audio, &1}) ++
          [:generation_complete]

      {:release, events}
    else
      {:error, :unverified_opening}
    end
  end

  def accept(_opening, event) when event in [:activity_start, :interrupted],
    do: {:error, :opening_interrupted}

  def accept(_opening, {:turn_complete, _status}), do: {:error, :unverified_opening}
  def accept(_opening, {:tool_call, _id, _name, _args}), do: {:error, :unexpected_tool}
  def accept(_opening, _metadata), do: :pass

  defp output_chunks(<<chunk::binary-size(@output_chunk_bytes), rest::binary>>),
    do: [chunk | output_chunks(rest)]

  defp output_chunks(<<>>), do: []
  defp output_chunks(tail), do: [tail]
end
