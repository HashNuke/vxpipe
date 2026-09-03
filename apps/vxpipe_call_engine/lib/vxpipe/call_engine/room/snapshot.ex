defmodule Vxpipe.CallEngine.Room.Snapshot do
  @moduledoc """
  The public state of one logical room.
  """

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :lifecycle,
    :created_by_actor_id,
    :created_by_command_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          lifecycle: :open,
          created_by_actor_id: String.t(),
          created_by_command_id: String.t()
        }

  @spec to_public(t()) :: map()
  def to_public(%__MODULE__{} = snapshot) do
    %{
      "tenant_id" => snapshot.tenant_id,
      "room_id" => snapshot.room_id,
      "incarnation_id" => snapshot.incarnation_id,
      "lifecycle" => Atom.to_string(snapshot.lifecycle),
      "created_by_actor_id" => snapshot.created_by_actor_id,
      "created_by_command_id" => snapshot.created_by_command_id
    }
  end
end
