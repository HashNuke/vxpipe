defmodule Vxpipe.Providers.OpenAI.GPTLiveFixedOpening do
  @moduledoc "Private, bounded verification of a fixed greeting's acoustic burst."

  alias Vxpipe.CallEngine.Speech.Duplex.OutputSegmenter

  @maximum_bytes 2 * 1_024 * 1_024
  @maximum_fragments 4_096
  @chunk_bytes 128 * 1_024

  defstruct [
    :segmenter,
    :expected,
    :reference,
    :deadline,
    :timer,
    pcm: [],
    text: [],
    bytes: 0,
    received_bytes: 0,
    fragments: 0,
    text_bytes: 0,
    start_ms: nil,
    end_ms: 0,
    closed?: false
  ]

  def new(segmenter, text) do
    deadline = make_ref()
    timer = Process.send_after(self(), {:opening_deadline, deadline}, 30_000)
    %__MODULE__{segmenter: segmenter, expected: text, deadline: deadline, timer: timer}
  end

  def push_pcm(opening, pcm) do
    bytes = opening.received_bytes + byte_size(pcm)

    if bytes <= @maximum_bytes do
      feed(%{opening | received_bytes: bytes}, pcm)
    else
      {:error, :session_failed}
    end
  end

  def fragment(opening, fragment) do
    count = opening.fragments + 1
    bytes = opening.text_bytes + byte_size(fragment.text)

    if count <= @maximum_fragments and bytes <= byte_size(opening.expected) do
      {segmenter, events} = OutputSegmenter.fragment(opening.segmenter, fragment)
      collect(%{opening | segmenter: segmenter, fragments: count, text_bytes: bytes}, events)
    else
      {:error, :session_failed}
    end
  end

  defp feed(opening, <<>>), do: {:ok, opening}

  defp feed(opening, pcm) do
    size = min(byte_size(pcm), opening.segmenter.config.frame_bytes)
    <<piece::binary-size(size), rest::binary>> = pcm

    case OutputSegmenter.push_pcm(opening.segmenter, piece) do
      {segmenter, events} ->
        case collect(%{opening | segmenter: segmenter}, events) do
          {:ok, %{closed?: true} = opening} -> verify(opening, rest)
          {:ok, opening} -> feed(opening, rest)
          {:error, _reason} = error -> error
        end

      {:error, _reason, _segmenter} ->
        {:error, :session_failed}
    end
  end

  defp collect(opening, events) do
    Enum.reduce_while(events, {:ok, opening}, fn event, {:ok, opening} ->
      case collect_event(opening, event) do
        {:ok, opening} -> {:cont, {:ok, opening}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp collect_event(%{reference: nil} = opening, {:open, reference}) do
    {segmenter, events} = OutputSegmenter.admitted(opening.segmenter, reference)
    collect(%{opening | reference: reference, segmenter: segmenter}, events)
  end

  defp collect_event(%{reference: reference} = opening, {:audio, reference, pcm}) do
    bytes = opening.bytes + byte_size(pcm)

    if bytes <= @maximum_bytes,
      do: {:ok, %{opening | pcm: [pcm | opening.pcm], bytes: bytes}},
      else: {:error, :session_failed}
  end

  defp collect_event(
         %{reference: reference} = opening,
         {:transcript, reference, text, start_ms, end_ms}
       ) do
    start_ms = if is_nil(opening.start_ms), do: start_ms, else: min(start_ms, opening.start_ms)

    {:ok,
     %{
       opening
       | text: [text | opening.text],
         start_ms: start_ms,
         end_ms: max(end_ms, opening.end_ms)
     }}
  end

  defp collect_event(%{reference: reference} = opening, {:close, reference}),
    do: {:ok, %{opening | closed?: true}}

  defp collect_event(_opening, _event), do: {:error, :session_failed}

  defp verify(opening, rest) do
    text = opening.text |> Enum.reverse() |> IO.iodata_to_binary()
    duration_ms = div(opening.bytes * 1_000, opening.segmenter.config.sample_rate * 2)

    if text == opening.expected and opening.bytes > 0 and
         is_integer(opening.start_ms) and opening.end_ms <= duration_ms and
         opening.segmenter.held == [] do
      Process.cancel_timer(opening.timer)
      pcm = opening.pcm |> Enum.reverse() |> IO.iodata_to_binary()

      verified = %{
        reference: opening.reference,
        segmenter: opening.segmenter,
        chunks: chunks(pcm),
        bytes: opening.bytes,
        fragment: {text, opening.start_ms, opening.end_ms}
      }

      {:verified, verified, rest}
    else
      {:error, :session_failed}
    end
  end

  defp chunks(<<>>), do: []
  defp chunks(pcm) when byte_size(pcm) <= @chunk_bytes, do: [pcm]
  defp chunks(<<chunk::binary-size(@chunk_bytes), rest::binary>>), do: [chunk | chunks(rest)]
end
