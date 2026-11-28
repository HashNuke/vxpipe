defmodule Vxpipe.Calls.ArchiveSanitizer do
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
  @spec sanitize(JSON.t()) :: JSON.t()
  def sanitize(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _nested_value} -> credential_key?(key) end)
    |> Map.new(fn {key, nested_value} -> {key, sanitize(nested_value)} end)
  end

  def sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  def sanitize(value), do: value

  @spec filter_payload(JSON.t(), atom(), map()) :: JSON.t()
  def filter_payload(payload, kind, source_policy) do
    Vxpipe.CallEngine.Archive.Policy.filter_payload(kind, payload, source_policy)
  end

  defp credential_key?(key) do
    normalized = key |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")
    MapSet.member?(@credential_keys, normalized)
  end
end
