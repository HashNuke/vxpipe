defmodule Vxpipe.CallEngine.CallSpec.Capabilities do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  @kinds [
    :speech_to_text,
    :model_inference,
    :text_to_speech,
    :speech_to_speech,
    :output_speech_to_text
  ]

  defstruct speech_to_text: nil,
            model_inference: nil,
            text_to_speech: nil,
            speech_to_speech: nil,
            output_speech_to_text: nil

  @type t :: %__MODULE__{
          speech_to_text: nil | CapabilitySelection.t(),
          model_inference: nil | CapabilitySelection.t(),
          text_to_speech: nil | CapabilitySelection.t(),
          speech_to_speech: nil | CapabilitySelection.t(),
          output_speech_to_text: nil | CapabilitySelection.t()
        }

  def new(value, path) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <- CallSpecValidation.normalize_map(value, @kinds, code, message, path),
         {:ok, speech_to_text} <- optional_selection(input, :speech_to_text, path),
         {:ok, model_inference} <- optional_selection(input, :model_inference, path),
         {:ok, text_to_speech} <- optional_selection(input, :text_to_speech, path),
         {:ok, speech_to_speech} <- optional_selection(input, :speech_to_speech, path),
         {:ok, output_speech_to_text} <- optional_selection(input, :output_speech_to_text, path) do
      {:ok,
       %__MODULE__{
         speech_to_text: speech_to_text,
         model_inference: model_inference,
         text_to_speech: text_to_speech,
         speech_to_speech: speech_to_speech,
         output_speech_to_text: output_speech_to_text
       }}
    end
  end

  def ref(%__MODULE__{speech_to_text: ref}, :speech_to_text), do: ref
  def ref(%__MODULE__{model_inference: ref}, :model_inference), do: ref
  def ref(%__MODULE__{text_to_speech: ref}, :text_to_speech), do: ref
  def ref(%__MODULE__{speech_to_speech: ref}, :speech_to_speech), do: ref
  def ref(%__MODULE__{output_speech_to_text: ref}, :output_speech_to_text), do: ref

  defp optional_selection(input, key, path) do
    case Map.fetch(input, key) do
      {:ok, value} ->
        CapabilitySelection.new(value, key, path ++ [Atom.to_string(key)])

      :error ->
        {:ok, nil}
    end
  end
end
