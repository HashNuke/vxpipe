defmodule Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding do
  @moduledoc false

  @enforce_keys [:name, :type, :action]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: String.t(), type: :host, action: module()}
end
