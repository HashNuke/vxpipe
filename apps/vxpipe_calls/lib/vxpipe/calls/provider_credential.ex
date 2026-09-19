defmodule Vxpipe.Calls.ProviderCredential do
  @moduledoc "Non-secret identity and lifecycle metadata for a scoped provider binding."

  @enforce_keys [:id, :tenant_key, :provider, :name, :auth_kind]
  defstruct @enforce_keys ++
              [
                owner: nil,
                version: 1,
                payload_schema_version: 1,
                status: :active,
                secret_hints: %{},
                last_validated_at: nil,
                encryption_key_id: nil,
                inserted_at: nil,
                updated_at: nil
              ]

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t() | nil,
          owner: :platform | {:tenant, String.t()} | nil,
          provider: String.t(),
          name: String.t(),
          auth_kind: String.t(),
          version: pos_integer(),
          payload_schema_version: pos_integer(),
          status: :active | :revoked,
          secret_hints: %{optional(String.t()) => String.t()},
          last_validated_at: DateTime.t() | nil,
          encryption_key_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  def owner(%__MODULE__{owner: :platform, tenant_key: nil}), do: :platform
  def owner(%__MODULE__{owner: nil, tenant_key: key}) when is_binary(key), do: {:tenant, key}
  def owner(%__MODULE__{owner: {:tenant, key}, tenant_key: key}), do: {:tenant, key}
  def owner(_credential), do: :invalid

  def owner_tag(:platform), do: :platform
  def owner_tag({:tenant, key}), do: {:tenant, key}
  def owner_tag(key) when is_binary(key), do: {:tenant, key}
  def owner_key(:platform), do: nil
  def owner_key({:tenant, key}), do: key
  def owner_key(key) when is_binary(key), do: key

  def available_to?(credential, tenant_key) do
    owner(credential) in [:platform, {:tenant, tenant_key}]
  end

  def binding_identity(credential) do
    case owner(credential) do
      :platform -> %{"id" => credential.id, "scope" => "platform", "tenant_key" => nil}
      {:tenant, key} -> %{"id" => credential.id, "scope" => "tenant", "tenant_key" => key}
    end
  end
end
