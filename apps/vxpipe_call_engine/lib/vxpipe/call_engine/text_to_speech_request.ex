defmodule Vxpipe.CallEngine.TextToSpeechRequest do
  @moduledoc false

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :source_participant_id,
    :connection_id,
    :command_id,
    :correlation_id,
    :output_id,
    :text,
    :output_sink
  ]
  @derive {Inspect,
           only: [
             :tenant_id,
             :room_id,
             :incarnation_id,
             :participant_id,
             :source_participant_id,
             :connection_id,
             :command_id,
             :correlation_id,
             :output_id,
             :purpose
           ]}
  defstruct @enforce_keys ++ [purpose: :agent_turn, source_policy: %{}]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          source_participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          output_id: String.t(),
          text: String.t(),
          output_sink: pid(),
          purpose: :agent_turn | :opening_audio,
          source_policy: map()
        }
end
