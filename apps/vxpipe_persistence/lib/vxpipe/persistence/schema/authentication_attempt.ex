defmodule Vxpipe.Persistence.Schema.AuthenticationAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "authentication_attempts" do
    field(:normalized_account, :string)
    field(:client_address, :string)
    field(:attempted_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attempt, attributes) do
    attempt
    |> cast(attributes, [:normalized_account, :client_address, :attempted_at])
    |> validate_required([:normalized_account, :client_address, :attempted_at])
    |> validate_length(:normalized_account, min: 1, max: 320)
    |> validate_length(:client_address, min: 1, max: 128)
  end
end
