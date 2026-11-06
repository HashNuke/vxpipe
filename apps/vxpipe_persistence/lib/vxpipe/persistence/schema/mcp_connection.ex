defmodule Vxpipe.Persistence.Schema.MCPConnection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenant_mcp_connections" do
    field(:public_id, Ecto.UUID)
    belongs_to(:tenant, Vxpipe.Persistence.Schema.Tenant)
    field(:endpoint, :string)
    field(:endpoint_identity, :string)
    field(:directory_id, :string)
    field(:directory_entry, :map)
    field(:server_name, :string)
    field(:auth_method, :string)
    field(:generation, :integer)
    field(:status, :string)
    field(:catalog, :map)
    field(:encrypted_payload, :binary, redact: true)
    field(:encryption_key_id, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attributes) do
    record
    |> cast(attributes, [
      :public_id,
      :tenant_id,
      :endpoint,
      :endpoint_identity,
      :directory_id,
      :directory_entry,
      :server_name,
      :auth_method,
      :generation,
      :status,
      :catalog,
      :encrypted_payload,
      :encryption_key_id
    ])
    |> validate_required([
      :public_id,
      :tenant_id,
      :endpoint,
      :endpoint_identity,
      :server_name,
      :auth_method,
      :generation,
      :status,
      :catalog
    ])
    |> validate_length(:endpoint, max: 2048)
    |> validate_length(:endpoint_identity, max: 2048)
    |> validate_length(:directory_id, max: 129)
    |> validate_length(:server_name, max: 200)
    |> validate_number(:generation, greater_than: 0)
    |> validate_inclusion(:auth_method, ~w(none bearer headers basic oauth))
    |> validate_inclusion(:status, ~w(connected revoked))
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:public_id)
    |> unique_constraint(:endpoint_identity,
      name: :tenant_mcp_connections_tenant_id_endpoint_identity_index
    )
    |> unique_constraint(:directory_id,
      name: :tenant_mcp_connections_tenant_id_directory_id_index
    )
  end
end
