defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Output do
  @moduledoc """
  The Morse duplex provider's continuous output timeline.

  Replies (caller replies and tool replies) are appended in order and drained
  as one clock-paced stream: leading silence, the reply audio, trailing
  silence. The energy gate splits the stream into bursts, so the timeline never
  needs to know where a reply ends. Pure and clock-free; `advance/2` starts the
  next queued reply only once the previous stream is exhausted and the
  segmenter has closed its burst.
  """

  @maximum_queued_replies 16

  @enforce_keys [:leading_silence, :trailing_silence]
  defstruct [:leading_silence, :trailing_silence, output: nil, queued: []]

  @type t :: %__MODULE__{}

  @spec new(binary(), binary()) :: t()
  def new(leading_silence, trailing_silence)
      when is_binary(leading_silence) and is_binary(trailing_silence) do
    %__MODULE__{leading_silence: leading_silence, trailing_silence: trailing_silence}
  end

  @spec idle?(t()) :: boolean()
  def idle?(%__MODULE__{output: nil, queued: []}), do: true
  def idle?(%__MODULE__{}), do: false

  @doc "The text of the reply currently streaming, or the empty string."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{output: %{text: text}}), do: text
  def text(%__MODULE__{}), do: ""

  @spec enqueue(t(), map()) :: {:ok, t()} | {:error, :pending_reply_overflow}
  def enqueue(%__MODULE__{queued: queued} = state, reply) do
    if length(queued) >= @maximum_queued_replies,
      do: {:error, :pending_reply_overflow},
      else: {:ok, %{state | queued: queued ++ [reply]}}
  end

  @spec advance(t(), boolean()) :: t()
  def advance(%__MODULE__{output: nil} = state, segmenter_open?) do
    if not segmenter_open? and state.queued != [] do
      [reply | rest] = state.queued
      %{state | output: begin_stream(state, reply), queued: rest}
    else
      state
    end
  end

  def advance(%__MODULE__{output: %{cursor: cursor, stream: stream}} = state, segmenter_open?) do
    if cursor >= byte_size(stream) do
      state |> Map.put(:output, nil) |> advance(segmenter_open?)
    else
      state
    end
  end

  @doc "The next frame of output audio, or silence when nothing is streaming."
  @spec next_frame(t(), pos_integer(), binary()) :: {binary(), t()}
  def next_frame(%__MODULE__{output: nil} = state, _frame_bytes, silence_frame),
    do: {silence_frame, state}

  def next_frame(%__MODULE__{output: output} = state, frame_bytes, silence_frame) do
    if output.cursor < byte_size(output.stream) do
      size = min(frame_bytes, byte_size(output.stream) - output.cursor)
      frame = binary_part(output.stream, output.cursor, size)
      {frame, %{state | output: %{output | cursor: output.cursor + size}}}
    else
      {silence_frame, state}
    end
  end

  @doc "Stop the current reply mid-stream; queued replies are kept."
  @spec stop(t()) :: t()
  def stop(%__MODULE__{output: nil} = state), do: state

  def stop(%__MODULE__{output: %{stream: stream} = output} = state),
    do: %{state | output: %{output | cursor: byte_size(stream)}}

  defp begin_stream(state, reply) do
    stream = state.leading_silence <> reply.pcm <> state.trailing_silence
    %{text: reply.text, stream: stream, cursor: 0}
  end
end
