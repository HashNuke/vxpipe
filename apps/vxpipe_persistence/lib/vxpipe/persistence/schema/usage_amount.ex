defmodule Vxpipe.Persistence.Schema.UsageAmount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Call

  @derive {Inspect, except: [:provider, :attribution]}

  schema "usage_amounts" do
    field(:public_id, :string)
    field(:attempt_id, :string)

    field(:capability, Ecto.Enum,
      values: [:model_inference, :speech_to_text, :text_to_speech, :tool, :telephony]
    )

    field(:provider, :map)
    field(:attribution, :map)
    field(:component, :string)

    field(:unit, Ecto.Enum,
      values: [:tokens, :characters, :milliseconds, :requests, :currency]
    )

    field(:currency, :string)
    field(:quantity, :decimal)
    field(:mode, Ecto.Enum, values: [:delta, :cumulative])
    field(:status, Ecto.Enum, values: [:estimate, :final, :correction])

    field(:provenance, Ecto.Enum,
      values: [:provider_reported, :locally_measured, :library_estimate, :billing_lookup]
    )

    field(:included_in, :string)
    field(:observation_ids, {:array, :string})
    belongs_to(:call, Call)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(amount, attributes) do
    amount
    |> cast(attributes, [
      :public_id,
      :call_id,
      :attempt_id,
      :capability,
      :provider,
      :attribution,
      :component,
      :unit,
      :currency,
      :quantity,
      :mode,
      :status,
      :provenance,
      :included_in,
      :observation_ids
    ])
    |> validate_required([
      :public_id,
      :call_id,
      :attempt_id,
      :capability,
      :provider,
      :attribution,
      :component,
      :unit,
      :quantity,
      :mode,
      :status,
      :provenance,
      :observation_ids
    ])
    |> validate_length(:public_id, min: 1, max: 128)
    |> validate_length(:attempt_id, min: 1, max: 128)
    |> validate_length(:component, min: 1, max: 64)
    |> validate_length(:currency, is: 3)
    |> validate_length(:included_in, min: 1, max: 64)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint([:call_id, :public_id])
    |> check_constraint(:capability, name: :usage_amounts_capability)
    |> check_constraint(:unit, name: :usage_amounts_unit)
    |> check_constraint(:currency, name: :usage_amounts_currency)
    |> check_constraint(:quantity, name: :usage_amounts_quantity)
    |> check_constraint(:mode, name: :usage_amounts_mode)
    |> check_constraint(:status, name: :usage_amounts_status)
    |> check_constraint(:provenance, name: :usage_amounts_provenance)
    |> check_constraint(:observation_ids, name: :usage_amounts_observation_ids)
  end
end
