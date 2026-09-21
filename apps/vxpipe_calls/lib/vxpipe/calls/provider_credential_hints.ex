defmodule Vxpipe.Calls.ProviderCredentialHints do
  @moduledoc "Derives bounded, non-secret credential hints for operator inventory views."

  alias Vxpipe.Providers.Registry

  @spec from_payload(String.t(), map()) :: %{optional(String.t()) => String.t()}
  def from_payload(provider, payload) do
    case Registry.resolve_capability(provider, :credential) do
      {:ok, schema} ->
        Enum.reduce(schema.preview_fields(), %{}, fn
          %{field: field, display: :last_four}, hints ->
            case Map.get(payload, field) do
              value when is_binary(value) -> Map.put(hints, field, last_four(value))
              _missing -> hints
            end

          _masked, hints ->
            hints
        end)

      {:error, _reason} ->
        %{}
    end
  end

  defp last_four(value) when is_binary(value), do: String.slice(value, -4, 4)
end
