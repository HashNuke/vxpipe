defmodule Vxpipe.CallEngine.CallVariables.UpdateSnapshot do
  @moduledoc """
  Private archival handoff for an accepted Call Variables update.
  """

  @derive {Inspect, except: [:sections]}
  @enforce_keys [
    :id,
    :command_id,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :activation_id,
    :source_participant_id,
    :correlation_id,
    :tool_call_id,
    :section,
    :section_revision,
    :global_revision,
    :sections,
    :source_policy,
    :occurred_at
  ]
  defstruct @enforce_keys

  @type section_snapshot :: %{revision: non_neg_integer(), value: nil | map()}
  @type t :: %__MODULE__{
          id: String.t(),
          command_id: String.t(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          activation_id: String.t(),
          source_participant_id: String.t(),
          correlation_id: String.t(),
          tool_call_id: String.t(),
          section: String.t(),
          section_revision: non_neg_integer(),
          global_revision: non_neg_integer(),
          sections: %{String.t() => section_snapshot()},
          source_policy: map(),
          occurred_at: DateTime.t()
        }
end
