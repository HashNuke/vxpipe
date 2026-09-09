defmodule Vxpipe.CallEngine.Archive.Sanitizer do
  @moduledoc false

  @credential_keys MapSet.new([
                     "accesstoken",
                     "apikey",
                     "authorization",
                     "clientsecret",
                     "cookie",
                     "password",
                     "proxyauthorization",
                     "refreshtoken",
                     "secret",
                     "setcookie",
                     "xapikey"
                   ])

  @spec sanitize(term()) :: JSON.t()
  def sanitize(value)
      when is_binary(value) or is_boolean(value) or is_number(value) or is_nil(value),
      do: value

  def sanitize(value) when is_atom(value), do: Atom.to_string(value)
  def sanitize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def sanitize(%_module{} = value), do: value |> Map.from_struct() |> sanitize()

  def sanitize(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {sanitize_key(key), nested_value}
    end)
    |> Enum.reject(fn {key, _nested_value} -> credential_key?(key) end)
    |> Map.new(fn {key, nested_value} -> {key, sanitize(nested_value)} end)
  end

  def sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  def sanitize(value) when is_tuple(value), do: value |> Tuple.to_list() |> sanitize()
  def sanitize(_value), do: "[unsupported]"

  defp sanitize_key(key) when is_binary(key), do: key
  defp sanitize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp sanitize_key(key) when is_integer(key), do: Integer.to_string(key)
  defp sanitize_key(_key), do: "[unsupported-key]"

  defp credential_key?(key) do
    normalized = key |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")
    MapSet.member?(@credential_keys, normalized)
  end
end
