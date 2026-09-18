defmodule Vxpipe.CallEngine.CallDefinition.VariableSection do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.VariableSchema
  alias Vxpipe.CallEngine.DefinitionValidation

  @derive {Inspect, except: [:validator]}
  @enforce_keys [:name, :schema, :validator]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: String.t(), schema: map(), validator: JSV.Root.t()}

  def new(name, value, path) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    with {:ok, name} <- DefinitionValidation.identifier(name, code, message, path),
         {:ok, input} <-
           DefinitionValidation.normalize_map(value, [:schema], code, message, path),
         {:ok, schema} <- DefinitionValidation.fetch(input, :schema, code, message, path),
         {:ok, validator} <- VariableSchema.compile(schema, path ++ ["schema"]) do
      {:ok, %__MODULE__{name: name, schema: schema, validator: validator}}
    end
  end
end
