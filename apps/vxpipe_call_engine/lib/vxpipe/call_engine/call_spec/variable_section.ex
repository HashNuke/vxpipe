defmodule Vxpipe.CallEngine.CallSpec.VariableSection do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.VariableSchema
  alias Vxpipe.CallEngine.CallSpecValidation

  @derive {Inspect, except: [:validator]}
  @enforce_keys [:name, :schema, :validator]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: String.t(), schema: map(), validator: JSV.Root.t()}

  def new(name, value, path) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    with {:ok, name} <- CallSpecValidation.identifier(name, code, message, path),
         {:ok, input} <-
           CallSpecValidation.normalize_map(value, [:schema], code, message, path),
         {:ok, schema} <- CallSpecValidation.fetch(input, :schema, code, message, path),
         {:ok, validator} <- VariableSchema.compile(schema, path ++ ["schema"]) do
      {:ok, %__MODULE__{name: name, schema: schema, validator: validator}}
    end
  end
end
