defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.OutputRecognition do
  @moduledoc false
  @derive {Inspect, only: [:bytes]}
  defstruct finals: %{}, parts: [], bytes: 0

  def new, do: %__MODULE__{}

  def add(state, reference, text) do
    case Map.fetch(state.finals, reference) do
      {:ok, ^text} -> {:ok, state}
      {:ok, _different} -> {:error, :conflicting_final}
      :error -> append(state, reference, text)
    end
  end

  def text(state), do: state.parts |> Enum.reverse() |> Enum.join(" ")

  defp append(state, reference, text) do
    separator = if state.parts != [] and text != "", do: 1, else: 0
    bytes = state.bytes + byte_size(text) + separator

    if map_size(state.finals) < 64 and bytes <= 65_536 do
      {:ok,
       %{
         state
         | finals: Map.put(state.finals, reference, text),
           parts: if(text == "", do: state.parts, else: [text | state.parts]),
           bytes: bytes
       }}
    else
      {:error, :recognition_overflow}
    end
  end
end
