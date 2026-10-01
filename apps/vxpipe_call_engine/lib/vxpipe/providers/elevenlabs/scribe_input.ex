defmodule Vxpipe.Providers.ElevenLabs.ScribeInput do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.{ActivityBoundary, Silero}
  @frame_bytes 1_024
  @pre_roll_bytes 3_072
  @derive {Inspect, only: [:turn_ref]}
  defstruct [:turn_ref, :onset, boundary: nil, pending: "", pre_roll: ""]

  def new, do: %__MODULE__{boundary: ActivityBoundary.new()}

  def push(%__MODULE__{} = state, audio, probabilities) when is_list(probabilities) do
    combined = state.pending <> audio

    if Silero.valid_audio?(audio) and
         length(probabilities) == div(byte_size(combined), @frame_bytes) do
      frames(state, combined, probabilities, [])
    else
      {:error, :invalid_classification}
    end
  end

  def push(_state, _audio, _probabilities), do: {:error, :invalid_classification}

  defp frames(state, pending, [], actions),
    do: {:ok, %{state | pending: pending}, Enum.reverse(actions)}

  defp frames(state, <<frame::binary-size(@frame_bytes), rest::binary>>, [p | ps], actions) do
    with {:ok, boundary, events} <- ActivityBoundary.push(state.boundary, p) do
      {state, emitted} = advance(%{state | boundary: boundary}, frame, events)
      frames(state, rest, ps, Enum.reverse(emitted, actions))
    else
      _invalid -> {:error, :invalid_classification}
    end
  end

  defp advance(state, frame, [{:speech_started, onset}]) do
    ref = make_ref()
    audio = state.pre_roll <> frame

    {%{state | turn_ref: ref, onset: onset, pre_roll: ""},
     [{:speech_started, ref}, {:audio, ref, audio}]}
  end

  defp advance(state, frame, [{:speech_ended, endpoint}]) do
    duration = div(endpoint - state.onset, 16)
    actions = [{:audio, state.turn_ref, frame}, {:endpoint, state.turn_ref, duration}]
    {%{state | turn_ref: nil, onset: nil, pre_roll: ""}, actions}
  end

  defp advance(%{turn_ref: ref} = state, frame, []) when is_reference(ref),
    do: {state, [{:audio, ref, frame}]}

  defp advance(state, frame, []) do
    audio = state.pre_roll <> frame
    size = min(byte_size(audio), @pre_roll_bytes)
    pre_roll = binary_part(audio, byte_size(audio) - size, size)
    {%{state | pre_roll: pre_roll}, []}
  end
end
