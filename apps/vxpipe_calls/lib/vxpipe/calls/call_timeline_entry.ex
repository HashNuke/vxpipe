defmodule Vxpipe.Calls.CallTimelineEntry do
  @moduledoc "One explicitly sourced item in an authorized call inspection timeline."

  alias Vxpipe.Calls.{CallFact, VariableSnapshot}

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :id,
    :kind,
    :source,
    :source_sequence,
    :occurred_at,
    :participant_id,
    :activation_id,
    :source_participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :tool_call_id,
    :variable_revision,
    :section_revision,
    :payload,
    :observed_duration_ms,
    :duration_basis
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          source: :persisted,
          source_sequence: pos_integer() | nil,
          occurred_at: DateTime.t(),
          participant_id: String.t() | nil,
          activation_id: String.t() | nil,
          source_participant_id: String.t() | nil,
          connection_id: String.t() | nil,
          command_id: String.t() | nil,
          correlation_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          variable_revision: non_neg_integer() | nil,
          section_revision: pos_integer() | nil,
          payload: map(),
          observed_duration_ms: non_neg_integer() | nil,
          duration_basis: :source_timestamps | nil
        }

  @spec from_fact(CallFact.t(), keyword()) :: t()
  def from_fact(%CallFact{} = fact, options \\ []) do
    %__MODULE__{
      id: fact.id,
      kind: fact.kind,
      source: :persisted,
      source_sequence: fact.sequence,
      occurred_at: fact.occurred_at,
      participant_id: fact.participant_id,
      activation_id: fact.activation_id,
      source_participant_id: fact.source_participant_id,
      connection_id: fact.connection_id,
      command_id: fact.command_id,
      correlation_id: fact.correlation_id,
      tool_call_id: fact.tool_call_id,
      variable_revision: nil,
      section_revision: nil,
      payload: fact.payload,
      observed_duration_ms: Keyword.get(options, :observed_duration_ms),
      duration_basis: Keyword.get(options, :duration_basis)
    }
  end

  @spec from_variable_snapshot(VariableSnapshot.t()) :: t()
  def from_variable_snapshot(%VariableSnapshot{} = snapshot) do
    %__MODULE__{
      id: snapshot.id,
      kind: :variable_snapshot,
      source: :persisted,
      source_sequence: nil,
      occurred_at: snapshot.occurred_at,
      participant_id: snapshot.participant_id,
      activation_id: snapshot.activation_id,
      source_participant_id: snapshot.source_participant_id,
      connection_id: nil,
      command_id: snapshot.command_id,
      correlation_id: snapshot.correlation_id,
      tool_call_id: snapshot.tool_call_id,
      variable_revision: snapshot.global_revision,
      section_revision: snapshot.section_revision,
      payload: snapshot.sections,
      observed_duration_ms: nil,
      duration_basis: nil
    }
  end
end
