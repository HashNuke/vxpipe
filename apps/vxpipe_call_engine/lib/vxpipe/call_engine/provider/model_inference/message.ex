defmodule Vxpipe.CallEngine.Provider.ModelInference.Message do
  @moduledoc false

  @enforce_keys [:role, :content]
  defstruct [:role, :content, :name, :tool_call_id, tool_calls: []]

  @type role :: :system | :user | :assistant | :tool
  @type t :: %__MODULE__{
          role: role(),
          content: String.t(),
          name: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [Vxpipe.CallEngine.Tool.Call.t()]
        }
end
