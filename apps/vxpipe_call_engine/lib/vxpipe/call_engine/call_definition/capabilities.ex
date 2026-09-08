defmodule Vxpipe.CallEngine.CallDefinition.Capabilities do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  @kinds [:speech_to_text, :model_inference, :text_to_speech]

  defstruct speech_to_text: nil, model_inference: nil, text_to_speech: nil

  @type t :: %__MODULE__{
          speech_to_text: nil | String.t(),
          model_inference: nil | String.t(),
          text_to_speech: nil | String.t()
        }

  def new(value, path) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    with {:ok, input} <- DefinitionValidation.normalize_map(value, @kinds, code, message, path),
         {:ok, speech_to_text} <- optional_ref(input, :speech_to_text, code, message, path),
         {:ok, model_inference} <- optional_ref(input, :model_inference, code, message, path),
         {:ok, text_to_speech} <- optional_ref(input, :text_to_speech, code, message, path) do
      {:ok,
       %__MODULE__{
         speech_to_text: speech_to_text,
         model_inference: model_inference,
         text_to_speech: text_to_speech
       }}
    end
  end

  def ref(%__MODULE__{speech_to_text: ref}, :speech_to_text), do: ref
  def ref(%__MODULE__{model_inference: ref}, :model_inference), do: ref
  def ref(%__MODULE__{text_to_speech: ref}, :text_to_speech), do: ref

  defp optional_ref(input, key, code, message, path) do
    case Map.fetch(input, key) do
      {:ok, value} ->
        DefinitionValidation.string(value, code, message, path ++ [Atom.to_string(key)],
          maximum: 128
        )

      :error ->
        {:ok, nil}
    end
  end
end
