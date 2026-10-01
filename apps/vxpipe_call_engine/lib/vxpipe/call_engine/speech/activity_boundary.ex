defmodule Vxpipe.CallEngine.Speech.ActivityBoundary do
  @moduledoc false

  @frame_samples 512
  @start_frames 4
  @stop_frames 16

  defstruct samples: 0, speaking?: false, speech_frames: 0, silence_frames: 0

  def new, do: %__MODULE__{}
  def reset(%__MODULE__{}), do: new()

  def push(%__MODULE__{} = state, probability)
      when is_number(probability) and probability >= 0 and probability <= 1 do
    {state, events} = classify(state, probability)
    {:ok, %{state | samples: state.samples + @frame_samples}, events}
  end

  def push(%__MODULE__{}, _probability), do: {:error, :invalid_probability}

  defp classify(%{speaking?: false} = state, probability) when probability >= 0.5 do
    frames = state.speech_frames + 1

    if frames == @start_frames do
      onset = state.samples - (@start_frames - 1) * @frame_samples
      {%{state | speaking?: true, speech_frames: 0}, [{:speech_started, onset}]}
    else
      {%{state | speech_frames: frames}, []}
    end
  end

  defp classify(%{speaking?: false} = state, _probability),
    do: {%{state | speech_frames: 0}, []}

  defp classify(%{speaking?: true} = state, probability) when probability < 0.35 do
    frames = state.silence_frames + 1

    if frames == @stop_frames do
      endpoint = state.samples - (@stop_frames - 1) * @frame_samples
      {%{state | speaking?: false, silence_frames: 0}, [{:speech_ended, endpoint}]}
    else
      {%{state | silence_frames: frames}, []}
    end
  end

  defp classify(%{speaking?: true} = state, _probability),
    do: {%{state | silence_frames: 0}, []}
end
