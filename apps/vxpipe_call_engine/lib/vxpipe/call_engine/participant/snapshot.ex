defmodule Vxpipe.CallEngine.Participant.Snapshot do
  @moduledoc """
  The public state of one participant admitted to a room incarnation.
  """

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :role,
    :state,
    :created_by_actor_id,
    :created_by_command_id
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          role: :agent | :human | :monitor,
          state: :joined,
          created_by_actor_id: String.t(),
          created_by_command_id: String.t()
        }

  @spec to_public(t()) :: map()
  def to_public(%__MODULE__{} = snapshot) do
    %{
      "tenant_id" => snapshot.tenant_id,
      "room_id" => snapshot.room_id,
      "incarnation_id" => snapshot.incarnation_id,
      "participant_id" => snapshot.participant_id,
      "role" => Atom.to_string(snapshot.role),
      "state" => Atom.to_string(snapshot.state),
      "created_by_actor_id" => snapshot.created_by_actor_id,
      "created_by_command_id" => snapshot.created_by_command_id
    }
  end
end
