defmodule Vxpipe.CallEngine.Event.AgentTurnCompleted do
  @moduledoc """
  Marks the end of one agent output turn for a participant connection.
  """

  @schema_version 1
  @enforce_keys [
    :id,
    :sequence,
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :source_participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :occurred_at
  ]
  defstruct @enforce_keys ++ [schema_version: @schema_version]

  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          sequence: pos_integer(),
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          source_participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          occurred_at: DateTime.t()
        }
end
