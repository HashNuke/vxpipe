defmodule Vxpipe.CallEngine.Provider.SpeechToText.Signal do
  @moduledoc false

  @maximum_provider_code_bytes 128
  @kinds [
    :connected,
    :transcript_updated,
    :turn_started,
    :eager_turn_ended,
    :turn_resumed,
    :turn_ended,
    :failed
  ]

  @enforce_keys [:kind, :provider_sequence]
  defstruct @enforce_keys ++
              [
                :policy_revision,
                :request_id,
                :provider_turn_index,
                :audio_duration_ms,
                :text,
                :end_of_turn_confidence,
                :trigger,
                :provider_code
              ]

  @type kind ::
          :connected
          | :transcript_updated
          | :turn_started
          | :eager_turn_ended
          | :turn_resumed
          | :turn_ended
          | :failed

  @type t :: %__MODULE__{
          kind: kind(),
          provider_sequence: non_neg_integer(),
          policy_revision: non_neg_integer() | nil,
          request_id: String.t() | nil,
          provider_turn_index: non_neg_integer() | nil,
          audio_duration_ms: non_neg_integer() | nil,
          text: String.t() | nil,
          end_of_turn_confidence: number() | nil,
          trigger: String.t() | nil,
          provider_code: String.t() | nil
        }

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @spec maximum_provider_code_bytes() :: pos_integer()
  def maximum_provider_code_bytes, do: @maximum_provider_code_bytes
end
