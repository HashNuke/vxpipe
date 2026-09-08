defmodule Vxpipe.CallEngine.CallDefinition.ToolSelection do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  @enforce_keys [:name, :type, :tool]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: String.t(), type: :host, tool: String.t()}

  def new(name, value, path) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    with {:ok, name} <- DefinitionValidation.identifier(name, code, message, path),
         :ok <- reject_reserved(name, code, message, path),
         {:ok, input} <-
           DefinitionValidation.normalize_map(value, [:type, :tool], code, message, path),
         {:ok, type_input} <- DefinitionValidation.fetch(input, :type, code, message, path),
         {:ok, type} <-
           DefinitionValidation.enum(type_input, [host: "host"], code, message, path ++ ["type"]),
         {:ok, tool_input} <- DefinitionValidation.fetch(input, :tool, code, message, path),
         {:ok, tool} <-
           DefinitionValidation.identifier(tool_input, code, message, path ++ ["tool"]) do
      {:ok, %__MODULE__{name: name, type: type, tool: tool}}
    end
  end

  defp reject_reserved(name, code, message, path)
       when name in ["transfer", "read_variables", "update_variables", "update_variable"] do
    DefinitionValidation.invalid(code, message, path, "collides with a platform tool name")
  end

  defp reject_reserved(_name, _code, _message, _path), do: :ok
end
