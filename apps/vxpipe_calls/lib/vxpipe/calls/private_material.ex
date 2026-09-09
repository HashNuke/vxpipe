defmodule Vxpipe.Calls.PrivateMaterial do
  @moduledoc false

  @names ["api_key", "authorization", "credential", "password", "secret", "token"]

  @spec present?(term()) :: boolean()
  def present?(value) when is_map(value) do
    Enum.any?(value, fn {key, nested} -> private_key?(key) or present?(nested) end)
  end

  def present?(value) when is_list(value), do: Enum.any?(value, &present?/1)
  def present?(_value), do: false

  defp private_key?(key) when is_atom(key), do: private_key?(Atom.to_string(key))

  defp private_key?(key) when is_binary(key) do
    normalized = String.downcase(key)

    Enum.any?(@names, fn name ->
      normalized == name or String.ends_with?(normalized, "_#{name}")
    end)
  end

  defp private_key?(_key), do: false
end
