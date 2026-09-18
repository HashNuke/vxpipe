defmodule Vxpipe.CallEngine.CallSpec.CallVariables do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.VariableSection
  alias Vxpipe.CallEngine.CallSpecValidation

  defstruct sections: %{}

  @type t :: %__MODULE__{sections: %{optional(String.t()) => VariableSection.t()}}

  def new(value) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:sections], code, message, [
             "call_variables"
           ]),
         {:ok, sections} <- sections(Map.get(input, :sections, %{}), code, message) do
      {:ok, %__MODULE__{sections: sections}}
    end
  end

  defp sections(value, _code, _message) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {name, section_input}, {:ok, sections} when is_binary(name) ->
        path = ["call_variables", "sections", name]

        case VariableSection.new(name, section_input, path) do
          {:ok, section} -> {:cont, {:ok, Map.put(sections, name, section)}}
          {:error, _error} = error -> {:halt, error}
        end

      {_name, _section_input}, _acc ->
        {:halt,
         CallSpecValidation.invalid(
           :invalid_call_spec,
           "The call spec is invalid.",
           ["call_variables", "sections", "<invalid-key>"],
           "section names must be strings"
         )}
    end)
  end

  defp sections(_value, code, message) do
    CallSpecValidation.invalid(
      code,
      message,
      ["call_variables", "sections"],
      "must be an object"
    )
  end
end
