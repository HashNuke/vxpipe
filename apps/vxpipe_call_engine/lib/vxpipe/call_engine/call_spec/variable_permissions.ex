defmodule Vxpipe.CallEngine.CallSpec.VariablePermissions do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpecValidation

  defstruct grants: %{}

  @type grant :: :read | :read_write
  @type t :: %__MODULE__{grants: %{optional(String.t()) => grant()}}

  def new(value, path) when is_map(value) do
    code = :invalid_call_spec
    message = "The call spec is invalid."

    Enum.reduce_while(value, {:ok, %{}}, fn
      {section, permissions}, {:ok, grants} when is_binary(section) ->
        permission_path = path ++ [section]

        with {:ok, section} <-
               CallSpecValidation.identifier(section, code, message, permission_path),
             {:ok, grant} <- grant(permissions, code, message, permission_path) do
          {:cont, {:ok, Map.put(grants, section, grant)}}
        else
          {:error, _error} = error -> {:halt, error}
        end

      {_section, _permissions}, _acc ->
        {:halt,
         CallSpecValidation.invalid(
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
    CallSpecValidation.invalid(
      :invalid_call_spec,
      "The call spec is invalid.",
      path,
      "must be an object"
    )
  end

  defp grant(permissions, code, message, path) when is_list(permissions) do
    permission_set = MapSet.new(permissions)

    cond do
      MapSet.size(permission_set) != length(permissions) ->
        CallSpecValidation.invalid(code, message, path, "must not contain duplicates")

      permission_set == MapSet.new(["read"]) ->
        {:ok, :read}

      permission_set == MapSet.new(["read", "write"]) ->
        {:ok, :read_write}

      true ->
        CallSpecValidation.invalid(
          code,
          message,
          path,
          "must grant read or read and write"
        )
    end
  end

  defp grant(_permissions, code, message, path) do
    CallSpecValidation.invalid(code, message, path, "must be an array")
  end
end
