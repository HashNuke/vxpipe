defmodule Vxpipe.Providers.ElevenLabs.ScribeTurn do
  @moduledoc false

  alias Vxpipe.Providers.ElevenLabs.Scribe

  @segment_bytes 20 * 32_000
  @text_bytes 65_536
  @derive {Inspect, only: [:segment_bytes, :waiting?, :ended?, :finished?]}
  defstruct [
    :turn_ref,
    segment_bytes: 0,
    text: "",
    partial_text: "",
    remainder: "",
    waiting?: false,
    ended?: false,
    finished?: false
  ]

  def new(turn_ref) when is_reference(turn_ref), do: %__MODULE__{turn_ref: turn_ref}

  def push_audio(%__MODULE__{ended?: true}, _audio), do: {:error, :input_closed}
  def push_audio(%__MODULE__{waiting?: true}, _audio), do: {:error, :busy}

  def push_audio(%__MODULE__{} = turn, audio) do
    with {:ok, _payload} <- Scribe.encode_audio(audio) do
      size = min(byte_size(audio), @segment_bytes - turn.segment_bytes)
      <<submitted::binary-size(size), remainder::binary>> = audio
      bytes = turn.segment_bytes + size
      waiting? = bytes == @segment_bytes
      actions = if waiting?, do: [{:audio, submitted}, :commit], else: [{:audio, submitted}]
      {:ok, %{turn | segment_bytes: bytes, waiting?: waiting?, remainder: remainder}, actions}
    else
      {:error, _reason} -> {:error, :invalid_audio}
    end
  end

  def partial(%__MODULE__{finished?: false, segment_bytes: bytes} = turn, text)
      when bytes > 0 and is_binary(text) do
    with {:ok, joined} <- snapshot(turn.text, text) do
      fragment = String.trim(text)

      if fragment == "" or fragment == turn.partial_text do
        {:ok, turn, []}
      else
        {:ok, %{turn | partial_text: fragment}, [{:transcript, turn.turn_ref, joined}]}
      end
    end
  end

  def partial(%__MODULE__{}, _text), do: {:error, :unexpected_segment}

  def end_turn(%__MODULE__{ended?: true} = turn), do: {:ok, turn, []}

  def end_turn(%__MODULE__{waiting?: true} = turn),
    do: {:ok, %{turn | ended?: true}, []}

  def end_turn(%__MODULE__{segment_bytes: 0} = turn),
    do: {:ok, %{turn | ended?: true, finished?: true}, [{:turn_ended, turn.turn_ref, turn.text}]}

  def end_turn(%__MODULE__{} = turn),
    do: {:ok, %{turn | ended?: true, waiting?: true}, [:commit]}

  def committed(%__MODULE__{waiting?: true} = turn, text) when is_binary(text) do
    with {:ok, joined} <- snapshot(turn.text, text) do
      events = [{:transcript, turn.turn_ref, joined}]

      settled = %{
        turn
        | text: joined,
          partial_text: "",
          segment_bytes: 0,
          waiting?: false,
          remainder: ""
      }

      continue_after_commit(settled, turn.remainder, events)
    end
  end

  def committed(%__MODULE__{}, _text), do: {:error, :unexpected_segment}

  defp continue_after_commit(%{ended?: true} = turn, "", events),
    do: {:ok, %{turn | finished?: true}, events ++ [{:turn_ended, turn.turn_ref, turn.text}]}

  defp continue_after_commit(turn, "", events), do: {:ok, turn, events}

  defp continue_after_commit(turn, remainder, events) do
    waiting? = turn.ended?
    actions = if waiting?, do: [{:audio, remainder}, :commit], else: [{:audio, remainder}]

    {:ok, %{turn | segment_bytes: byte_size(remainder), waiting?: waiting?}, events ++ actions}
  end

  defp snapshot(prefix, text) do
    if byte_size(text) <= @text_bytes and String.valid?(text) do
      joined = join(prefix, String.trim(text))
      if byte_size(joined) <= @text_bytes, do: {:ok, joined}, else: {:error, :invalid_segment}
    else
      {:error, :invalid_segment}
    end
  end

  defp join("", text), do: text
  defp join(text, ""), do: text
  defp join(prefix, text), do: prefix <> " " <> text
end
