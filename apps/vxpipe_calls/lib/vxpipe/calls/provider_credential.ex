defmodule Vxpipe.Calls.ProviderCredential do
  @moduledoc "Non-secret identity and lifecycle metadata for one tenant provider binding."

  @enforce_keys [:id, :tenant_key, :provider, :name, :auth_kind]
  defstruct @enforce_keys ++
              [
                version: 1,
                payload_schema_version: 1,
                status: :active,
                encryption_key_id: nil,
                inserted_at: nil,
                updated_at: nil
              ]

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          provider: String.t(),
          name: String.t(),
          auth_kind: String.t(),
          version: pos_integer(),
          payload_schema_version: pos_integer(),
          status: :active | :revoked,
          encryption_key_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
