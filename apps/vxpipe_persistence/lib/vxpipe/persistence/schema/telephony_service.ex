defmodule Vxpipe.Persistence.Schema.TelephonyService do
  use Ecto.Schema
  import Ecto.Changeset

  schema "telephony_services" do
    field(:public_id, Ecto.UUID)
    field(:name, :string)
    field(:ingress_key, :string)
    field(:provider, :string)
    field(:provider_connection_id, :string)
    field(:credential_id, Ecto.UUID)
    field(:credential_name, :string)
    field(:public_key, :string)
    field(:outbound_number, :string, redact: true)
    field(:answering_machine_detection, :string)
    field(:media_token_ttl_ms, :integer)
    field(:webhook_tolerance_seconds, :integer)
    belongs_to(:tenant, Vxpipe.Persistence.Schema.Tenant)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(service, attributes) do
    required = [
      :public_id,
      :tenant_id,
      :name,
      :ingress_key,
      :provider,
      :provider_connection_id,
      :answering_machine_detection,
      :media_token_ttl_ms,
      :webhook_tolerance_seconds
    ]

    service
    |> cast(attributes, [
      :outbound_number,
      :public_key,
      :credential_id,
      :credential_name | required
    ])
    |> validate_required(required)
    |> check_constraint(:public_key, name: :telephony_services_provider_public_key)
    |> check_constraint(:credential_name, name: :telephony_services_credential_binding)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:credential_id, name: :telephony_services_credential_owner_fkey)
    |> unique_constraint(:public_id)
    |> unique_constraint(:name, name: :telephony_services_tenant_id_name_index)
    |> unique_constraint(:ingress_key)
    |> unique_constraint(:provider_connection_id,
      name: :telephony_services_scoped_application_index
    )
  end
end
