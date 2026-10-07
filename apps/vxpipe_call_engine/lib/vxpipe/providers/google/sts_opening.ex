defmodule Vxpipe.Providers.Google.STSOpening do
  @moduledoc "Bounded fixed-opening assembly and available-transcript validation before playback."

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

      {:ok, cue,
       %{expected: text, transcript: "", chunks: [], audio_bytes: 0, generation_done?: false}}
    else
      {:error, :invalid_opening}
    end
  end

  def prepare(_opening), do: {:error, :invalid_opening}

  def accept(opening, {:output_transcript, text}) do
    transcript = opening.transcript <> text
    opening = %{opening | transcript: transcript}

    cond do
      not prefix?(words(transcript), words(opening.expected)) -> {:error, :text_mismatch}
      opening.generation_done? and verified?(opening) -> release(opening)
      true -> {:buffered, opening}
    end
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

  # Gemini can report generation completion before the opening's output transcription
  # arrives. Hold audio until the transcript verifies or the completed turn establishes
  # that no transcription was supplied.
  def accept(opening, :generation_complete) do
    cond do
      verified?(opening) -> release(opening)
      opening.chunks != [] -> {:buffered, %{opening | generation_done?: true}}
      true -> {:error, :unverified_opening}
    end
  end

  def accept(_opening, event) when event in [:activity_start, :interrupted],
    do: {:error, :opening_interrupted}

  def accept(opening, {:turn_complete, _status} = event) do
    if opening.generation_done? and opening.chunks != [] and opening.transcript == "" do
      {:release, audio_events(opening) ++ [event]}
    else
      {:error, :unverified_opening}
    end
  end

  def accept(_opening, {:tool_call, _id, _name, _args}), do: {:error, :unexpected_tool}
  def accept(_opening, _metadata), do: :pass

  # Speech transcription carries neither the author's punctuation nor case; compare words.
  defp verified?(opening),
    do: words(opening.transcript) == words(opening.expected) and opening.chunks != []

  defp words(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split()
  end

  # Fragments may split a word, so the last heard word only has to start the expected one.
  defp prefix?([], _expected), do: true
  defp prefix?([word], [expected | _rest]), do: String.starts_with?(expected, word)
  defp prefix?([word | heard], [word | expected]), do: prefix?(heard, expected)
  defp prefix?(_heard, _expected), do: false

  # The verified opening is published as the author's exact text.
  defp release(opening) do
    events =
      [{:output_transcript, opening.expected}] ++ audio_events(opening)

    {:release, events}
  end

  defp audio_events(opening) do
    Enum.map(output_chunks(IO.iodata_to_binary(opening.chunks)), &{:audio, &1}) ++
      [:generation_complete]
  end

  defp output_chunks(<<chunk::binary-size(@output_chunk_bytes), rest::binary>>),
    do: [chunk | output_chunks(rest)]

  defp output_chunks(<<>>), do: []
  defp output_chunks(tail), do: [tail]
end
