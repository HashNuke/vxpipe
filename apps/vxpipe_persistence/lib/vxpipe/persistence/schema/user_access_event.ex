defmodule Vxpipe.Persistence.Schema.UserAccessEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{ApiKey, IdentityRole, IdentityUser}

  schema "user_access_events" do
    field(:action, :string)
    field(:summary, :map)

    belongs_to(:actor_user, IdentityUser)
    belongs_to(:actor_api_key, ApiKey)
    belongs_to(:target_user, IdentityUser)
    belongs_to(:target_role, IdentityRole)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attributes) do
    event
    |> cast(attributes, [
      :actor_api_key_id,
      :actor_user_id,
      :target_user_id,
      :target_role_id,
      :action,
      :summary
    ])
    |> validate_required([:action])
    |> validate_length(:action, min: 1, max: 64)
    |> foreign_key_constraint(:actor_api_key_id)
    |> check_constraint(:actor_api_key_id, name: :user_access_events_single_actor)
    |> foreign_key_constraint(:actor_user_id)
    |> foreign_key_constraint(:target_user_id)
    |> foreign_key_constraint(:target_role_id)
  end
end
