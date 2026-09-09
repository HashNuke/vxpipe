defmodule Vxpipe.CallEngine.ResolvedCallPlan do
  @moduledoc """
  A self-contained immutable call plan pinned before live room startup.
  """

  alias Vxpipe.CallEngine.ResolvedCallPlan.{CallVariables, Participant, ToolVisibility}

  @enforce_keys [
    :definition_id,
    :definition_revision,
    :schema_version,
    :tenant_id,
    :actor_id,
    :call_id,
    :room_id,
    :transport,
    :entry_caller,
    :entry_receiver,
    :participants,
    :call_variables,
    :tool_visibility,
    :max_duration_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          definition_id: String.t(),
          definition_revision: pos_integer(),
          schema_version: String.t(),
          tenant_id: String.t(),
          actor_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          transport: :web,
          entry_caller: String.t(),
          entry_receiver: String.t(),
          participants: %{String.t() => Participant.t()},
          call_variables: CallVariables.t(),
          tool_visibility: ToolVisibility.t(),
          max_duration_ms: pos_integer()
        }
end
