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

  @decisions_kind [:decisions]

  defstruct speech_to_text: nil,
            model_inference: nil,
            text_to_speech: nil,
            speech_to_speech: nil,
            output_speech_to_text: nil,
            decisions: nil

  @type t :: %__MODULE__{
          speech_to_text: nil | CapabilitySelection.t(),
          model_inference: nil | CapabilitySelection.t(),
          text_to_speech: nil | CapabilitySelection.t(),
          speech_to_speech: nil | CapabilitySelection.t(),
          output_speech_to_text: nil | CapabilitySelection.t(),
          decisions: nil | CapabilitySelection.t()
        }

  def new(value, path, options \\ []) do
    code = :invalid_call_spec
    message = "The call spec is invalid."
    decisions? = Keyword.get(options, :decisions?, false)

    allowed = if decisions?, do: @kinds ++ @decisions_kind, else: @kinds

    with {:ok, input} <- CallSpecValidation.normalize_map(value, allowed, code, message, path),
         {:ok, speech_to_text} <- optional_selection(input, :speech_to_text, path),
         {:ok, model_inference} <- optional_selection(input, :model_inference, path),
         {:ok, text_to_speech} <- optional_selection(input, :text_to_speech, path),
         {:ok, speech_to_speech} <- optional_selection(input, :speech_to_speech, path),
         {:ok, output_speech_to_text} <- optional_selection(input, :output_speech_to_text, path),
         {:ok, decisions} <- decisions_selection(input, path, decisions?) do
      {:ok,
       %__MODULE__{
         speech_to_text: speech_to_text,
         model_inference: model_inference,
         text_to_speech: text_to_speech,
         speech_to_speech: speech_to_speech,
         output_speech_to_text: output_speech_to_text,
         decisions: decisions
       }}
    end
  end

  def ref(%__MODULE__{decisions: ref}, :decisions), do: ref

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

  defp decisions_selection(input, path, true) do
    optional_selection(input, :decisions, path)
  end

  defp decisions_selection(input, path, false) do
    if Map.has_key?(input, :decisions) do
      CallSpecValidation.invalid(
        :invalid_call_spec,
        "The call spec is invalid.",
        path ++ ["decisions"],
        "is not supported for this participant"
      )
    else
      {:ok, nil}
    end
  end
end
