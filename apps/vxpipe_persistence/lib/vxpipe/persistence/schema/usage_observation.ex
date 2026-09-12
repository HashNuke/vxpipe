defmodule Vxpipe.Persistence.Schema.UsageObservation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Call

  @derive {Inspect, except: [:provider, :attribution, :measurement]}

  schema "usage_observations" do
    field(:public_id, :string)
    field(:attempt_id, :string)

    field(:capability, Ecto.Enum,
      values: [:model_inference, :speech_to_text, :text_to_speech, :tool, :telephony]
    )

    field(:delivery_id, :string)
    field(:source_sequence, :integer)
    field(:provider, :map)
    field(:attribution, :map)
    field(:measurement, :map)

    field(:outcome, Ecto.Enum,
      values: [:in_progress, :succeeded, :failed, :cancelled, :unknown]
    )

    field(:observed_at, :utc_datetime_usec)
    belongs_to(:call, Call)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(observation, attributes) do
    observation
    |> cast(attributes, [
      :public_id,
      :call_id,
      :attempt_id,
      :capability,
      :delivery_id,
      :source_sequence,
      :provider,
      :attribution,
      :measurement,
      :outcome,
      :observed_at
    ])
    |> validate_required([
      :public_id,
      :call_id,
      :attempt_id,
      :capability,
      :provider,
      :attribution,
      :outcome,
      :observed_at
    ])
    |> validate_length(:public_id, min: 1, max: 128)
    |> validate_length(:attempt_id, min: 1, max: 128)
    |> validate_length(:delivery_id, min: 1, max: 128)
    |> validate_number(:source_sequence, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint([:call_id, :public_id])
    |> check_constraint(:capability, name: :usage_observations_capability)
    |> check_constraint(:outcome, name: :usage_observations_outcome)
    |> check_constraint(:source_sequence, name: :usage_observations_source_sequence)
  end
end
