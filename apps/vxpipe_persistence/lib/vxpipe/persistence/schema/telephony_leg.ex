defmodule Vxpipe.Persistence.Schema.TelephonyLeg do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{Call, Tenant}

  schema "telephony_legs" do
    field(:provider, :string)
    field(:service, :string)
    field(:provider_event_id, :string)
    field(:provider_connection_id, :string)
    field(:provider_call_control_id, :string)
    field(:provider_call_leg_id, :string)
    field(:provider_call_session_id, :string)
    field(:participant_ref, :string)
    field(:participant_id, :string)
    field(:state, :string)
    field(:accepted_at, :utc_datetime_usec)
    field(:incarnation_id, :string)

    belongs_to(:tenant, Tenant)
    belongs_to(:call, Call)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(leg, attributes) do
    leg
    |> cast(attributes, [
      :provider,
      :service,
      :provider_event_id,
      :provider_connection_id,
      :provider_call_control_id,
      :provider_call_leg_id,
      :provider_call_session_id,
      :participant_ref,
      :participant_id,
      :state,
      :accepted_at,
      :incarnation_id,
      :tenant_id,
      :call_id
    ])
    |> validate_required([
      :provider,
      :service,
      :provider_event_id,
      :provider_connection_id,
      :provider_call_control_id,
      :provider_call_leg_id,
      :provider_call_session_id,
      :participant_ref,
      :participant_id,
      :state,
      :accepted_at,
      :tenant_id,
      :call_id
    ])
    |> validate_inclusion(:provider, ["telnyx", "twilio"])
    |> validate_inclusion(:state, ["admitting", "active", "ended"])
    |> validate_lengths()
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint(:provider_event_id,
      name: :telephony_legs_provider_service_provider_event_id_index
    )
    |> unique_constraint(:provider_call_leg_id,
      name: :telephony_legs_provider_service_provider_call_leg_id_index
    )
  end

  defp validate_lengths(changeset) do
    Enum.reduce(
      [
        :service,
        :provider_event_id,
        :provider_connection_id,
        :provider_call_control_id,
        :provider_call_leg_id,
        :provider_call_session_id,
        :participant_ref,
        :participant_id,
        :incarnation_id
      ],
      changeset,
      &validate_length(&2, &1, min: 1, max: 128)
    )
  end
end
