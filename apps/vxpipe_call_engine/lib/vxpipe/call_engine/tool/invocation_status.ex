defmodule Vxpipe.CallEngine.Tool.InvocationStatus do
  @moduledoc false

  @enforce_keys [
    :invocation_id,
    :tool_name,
    :conversation_mode,
    :source_turn_id,
    :status
  ]
  defstruct @enforce_keys

  @type status :: :running | :terminal_queued | :completion_admitted
  @type t :: %__MODULE__{
          invocation_id: String.t(),
          tool_name: String.t(),
          conversation_mode: :blocking | :non_blocking,
          source_turn_id: String.t(),
          status: status()
        }
end
