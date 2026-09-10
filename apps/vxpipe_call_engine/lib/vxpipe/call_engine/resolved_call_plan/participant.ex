defmodule Vxpipe.CallEngine.ResolvedCallPlan.Participant do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.ConnectionIntent
  alias Vxpipe.CallEngine.CallDefinition.TransferHistory
  alias Vxpipe.CallEngine.CallDefinition.VariablePermissions
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, ToolBinding}

  @enforce_keys [
    :definition_key,
    :participant_id,
    :activation_id,
    :kind,
    :description,
    :connection,
    :prompt,
    :first_message,
    :first_message_text,
    :capabilities,
    :tools,
    :transfers,
    :transfer_history,
    :variable_permissions
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          definition_key: String.t(),
          participant_id: String.t(),
          activation_id: nil | String.t(),
          kind: :human | :agent,
          description: nil | String.t(),
          connection: nil | ConnectionIntent.t(),
          prompt: nil | String.t(),
          first_message: nil | atom(),
          first_message_text: nil | String.t(),
          capabilities: Capabilities.t(),
          tools: %{optional(String.t()) => ToolBinding.t()},
          transfers: [String.t()],
          transfer_history: nil | TransferHistory.t(),
          variable_permissions: VariablePermissions.t()
        }
end
