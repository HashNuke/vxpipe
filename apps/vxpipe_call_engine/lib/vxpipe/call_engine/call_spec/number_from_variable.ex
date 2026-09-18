defmodule Vxpipe.CallEngine.CallDefinition.NumberFromVariable do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  @enforce_keys [:section, :variable]
  defstruct @enforce_keys

  @type t :: %__MODULE__{section: String.t(), variable: String.t()}

  def new(value, path) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    with {:ok, input} <-
           DefinitionValidation.normalize_map(
             value,
             [:section, :variable],
             code,
             message,
             path
           ),
         {:ok, section_input} <- DefinitionValidation.fetch(input, :section, code, message, path),
         {:ok, section} <-
           DefinitionValidation.identifier(
             section_input,
             code,
             message,
             path ++ ["section"]
           ),
         {:ok, variable_input} <-
           DefinitionValidation.fetch(input, :variable, code, message, path),
         {:ok, variable} <-
           DefinitionValidation.identifier(
             variable_input,
             code,
             message,
             path ++ ["variable"]
           ) do
      {:ok, %__MODULE__{section: section, variable: variable}}
    end
  end
end
