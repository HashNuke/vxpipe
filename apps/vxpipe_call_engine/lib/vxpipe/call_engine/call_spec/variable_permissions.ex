defmodule Vxpipe.CallEngine.CallDefinition.VariablePermissions do
  @moduledoc false

  alias Vxpipe.CallEngine.DefinitionValidation

  defstruct grants: %{}

  @type grant :: :read | :read_write
  @type t :: %__MODULE__{grants: %{optional(String.t()) => grant()}}

  def new(value, path) when is_map(value) do
    code = :invalid_call_definition
    message = "The call definition is invalid."

    Enum.reduce_while(value, {:ok, %{}}, fn
      {section, permissions}, {:ok, grants} when is_binary(section) ->
        permission_path = path ++ [section]

        with {:ok, section} <-
               DefinitionValidation.identifier(section, code, message, permission_path),
             {:ok, grant} <- grant(permissions, code, message, permission_path) do
          {:cont, {:ok, Map.put(grants, section, grant)}}
        else
          {:error, _error} = error -> {:halt, error}
        end

      {_section, _permissions}, _acc ->
        {:halt,
         DefinitionValidation.invalid(
           code,
           message,
           path ++ ["<invalid-key>"],
           "section names must be strings"
         )}
    end)
    |> case do
      {:ok, grants} -> {:ok, %__MODULE__{grants: grants}}
      {:error, _error} = error -> error
    end
  end

  def new(_value, path) do
    DefinitionValidation.invalid(
      :invalid_call_definition,
      "The call definition is invalid.",
      path,
      "must be an object"
    )
  end

  defp grant(permissions, code, message, path) when is_list(permissions) do
    permission_set = MapSet.new(permissions)

    cond do
      MapSet.size(permission_set) != length(permissions) ->
        DefinitionValidation.invalid(code, message, path, "must not contain duplicates")

      permission_set == MapSet.new(["read"]) ->
        {:ok, :read}

      permission_set == MapSet.new(["read", "write"]) ->
        {:ok, :read_write}

      true ->
        DefinitionValidation.invalid(
          code,
          message,
          path,
          "must grant read or read and write"
        )
    end
  end

  defp grant(_permissions, code, message, path) do
    DefinitionValidation.invalid(code, message, path, "must be an array")
  end
end
