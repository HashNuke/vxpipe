defmodule Vxpipe.CallEngine.Tool.Context do
  @moduledoc false

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :agent_participant_id,
    :source_participant_id,
    :connection_id,
    :command_id,
    :correlation_id
  ]
  defstruct @enforce_keys ++
              [:agent_request_id, :tool_call_id, :source_capability, audio_response: false]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          agent_participant_id: String.t(),
          source_participant_id: String.t(),
          connection_id: String.t(),
          command_id: String.t(),
          correlation_id: String.t(),
          agent_request_id: nil | String.t(),
          tool_call_id: nil | String.t(),
          source_capability: nil | pid(),
          audio_response: boolean()
        }
end
