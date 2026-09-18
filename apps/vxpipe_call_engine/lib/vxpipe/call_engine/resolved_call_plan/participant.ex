defmodule Vxpipe.CallEngine.ResolvedCallPlan.Participant do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.ConnectionIntent
  alias Vxpipe.CallEngine.CallSpec.TransferHistory
  alias Vxpipe.CallEngine.CallSpec.VariablePermissions
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, MediaPolicy, ToolBinding}

  @enforce_keys [
    :call_spec_key,
    :participant_id,
    :activation_id,
    :kind,
    :description,
    :connection,
    :transfer_notice,
    :prompt,
    :first_message,
    :first_message_text,
    :capabilities,
    :while_present,
    :tools,
    :transfers,
    :transfer_history,
    :variable_permissions
  ]
  defstruct @enforce_keys ++ [telephony_service: nil]

  @type t :: %__MODULE__{
          call_spec_key: String.t(),
          participant_id: String.t(),
          activation_id: nil | String.t(),
          kind: :human | :agent,
          description: nil | String.t(),
          connection: nil | ConnectionIntent.t(),
          telephony_service: nil | Vxpipe.CallEngine.Telephony.ServiceReference.t(),
          transfer_notice: nil | String.t(),
          prompt: nil | String.t(),
          first_message: nil | atom(),
          first_message_text: nil | String.t(),
          capabilities: Capabilities.t(),
          while_present: MediaPolicy.t(),
          tools: %{optional(String.t()) => ToolBinding.t()},
          transfers: [String.t()],
          transfer_history: nil | TransferHistory.t(),
          variable_permissions: VariablePermissions.t()
        }
end
