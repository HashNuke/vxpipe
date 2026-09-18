defmodule Vxpipe.CallEngine.CallSpec.NumberFromVariable do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation

  @enforce_keys [:section, :variable]
  defstruct @enforce_keys

  @type t :: %__MODULE__{section: String.t(), variable: String.t()}

  def new(value, path) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, input} <-
           CallSpecValidation.normalize_map(
             value,
             [:section, :variable],
             code,
             message,
             path
           ),
         {:ok, section_input} <- CallSpecValidation.fetch(input, :section, code, message, path),
         {:ok, section} <-
           CallSpecValidation.identifier(
             section_input,
             code,
             message,
             path ++ ["section"]
           ),
         {:ok, variable_input} <-
           CallSpecValidation.fetch(input, :variable, code, message, path),
         {:ok, variable} <-
           CallSpecValidation.identifier(
             variable_input,
             code,
             message,
             path ++ ["variable"]
           ) do
      {:ok, %__MODULE__{section: section, variable: variable}}
    end
  end
end
