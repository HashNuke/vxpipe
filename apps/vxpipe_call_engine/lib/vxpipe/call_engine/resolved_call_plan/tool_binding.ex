defmodule Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.ResolvedTool

  @enforce_keys [:name, :type, :conversation_mode]
  defstruct @enforce_keys ++ [:action, :remote]

  @type t :: %__MODULE__{
          name: String.t(),
          type: :host | :mcp,
          conversation_mode: :blocking | :non_blocking,
          action: module() | nil,
          remote: ResolvedTool.t() | nil
        }
end
