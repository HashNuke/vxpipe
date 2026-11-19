defmodule Vxpipe.CallEngine.Room.Snapshot do
  @moduledoc """
  The public state of one logical room.
  """

  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.ResolvedCallPlan

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

  @doc false
  def new(%CreateRoom{} = command, incarnation_id, _options) do
    %__MODULE__{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: command.actor_id,
      created_by_command_id: command.id
    }
  end

  def new(%ResolvedCallPlan{} = plan, incarnation_id, options) do
    %__MODULE__{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: plan.actor_id,
      created_by_command_id: Keyword.fetch!(options, :start_command_id)
    }
  end

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
