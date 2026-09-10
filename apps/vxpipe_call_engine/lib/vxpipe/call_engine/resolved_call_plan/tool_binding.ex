defmodule Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding, as: TransferBinding

  @enforce_keys [:name, :type, :conversation_mode]
  defstruct @enforce_keys ++ [:action, :remote, :transfer]

  @type t :: %__MODULE__{
          name: String.t(),
          type: :host | :mcp | :participant_transfer | :platform,
          conversation_mode: :blocking | :non_blocking,
          action: module() | nil,
          remote: ResolvedTool.t() | nil,
          transfer: TransferBinding.t() | nil
        }
end
