defmodule Vxpipe.CallEngine.LiveInspection.Snapshot do
  @moduledoc "A bounded private projection of one currently live call."

  @derive {Inspect, except: [:records]}
  @enforce_keys [
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :records,
    :latest_fact_sequence,
    :latest_variable_revision,
    :dropped_records,
    :rejected_records
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          records: [struct()],
          latest_fact_sequence: pos_integer() | nil,
          latest_variable_revision: non_neg_integer() | nil,
          dropped_records: non_neg_integer(),
          rejected_records: non_neg_integer()
        }
end
