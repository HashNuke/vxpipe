defmodule Vxpipe.Persistence.Schema.ProviderCredential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "provider_credentials" do
    field(:scope, :string, default: "tenant")
    field(:public_id, Ecto.UUID)
    field(:provider, :string)
    field(:name, :string)
    field(:auth_kind, :string)
    field(:encrypted_payload, :binary, redact: true)
    field(:encryption_key_id, :string)
    field(:payload_schema_version, :integer)
    field(:version, :integer)
    field(:status, :string)
    field(:secret_hints, :map, default: %{})
    field(:last_validated_at, :utc_datetime_usec)
    belongs_to(:tenant, Vxpipe.Persistence.Schema.Tenant)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(credential, attributes) do
    fields = [
      :scope,
      :public_id,
      :provider,
      :name,
      :auth_kind,
      :encrypted_payload,
      :encryption_key_id,
      :payload_schema_version,
      :version,
      :status,
      :secret_hints,
      :last_validated_at,
      :tenant_id
    ]

    credential
    |> cast(attributes, fields)
    |> validate_required(fields -- [:last_validated_at, :tenant_id])
    |> validate_inclusion(:scope, ["platform", "tenant"])
    |> check_constraint(:scope, name: :provider_credentials_owner)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint(:public_id)
    |> unique_constraint(:name, name: :provider_credentials_tenant_id_provider_name_index)
    |> unique_constraint(:name, name: :provider_credentials_platform_provider_name_index)
  end
end
