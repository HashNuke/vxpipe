defmodule Vxpipe.Calls.PrivateMaterial do
  @moduledoc false

  @names ["api_key", "authorization", "credential", "password", "secret", "token"]

  @spec present?(term()) :: boolean()
  def present?(value), do: not is_nil(path(value))

  @doc "Returns the first private field path without including its value."
  def path(value), do: find_path(value, [])

  defp find_path(value, path) when is_map(value) do
    Enum.find_value(value, fn {key, nested} ->
      field_path = path ++ [display_key(key)]
      if private_key?(key), do: field_path, else: find_path(nested, field_path)
    end)
  end

  defp find_path(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.find_value(fn {nested, index} ->
      find_path(nested, path ++ [Integer.to_string(index)])
    end)
  end

  defp find_path(_value, _path), do: nil

  defp display_key(key) when is_atom(key), do: Atom.to_string(key)
  defp display_key(key) when is_binary(key), do: key
  defp display_key(_key), do: "<invalid-key>"

  defp private_key?(key) when is_atom(key), do: private_key?(Atom.to_string(key))

  defp private_key?(key) when is_binary(key) do
    normalized = String.downcase(key)

    Enum.any?(@names, fn name ->
      normalized == name or String.ends_with?(normalized, "_#{name}")
    end)
  end

  defp private_key?(_key), do: false
end
