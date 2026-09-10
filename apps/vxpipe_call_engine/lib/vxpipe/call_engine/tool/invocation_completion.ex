defmodule Vxpipe.CallEngine.Tool.InvocationCompletion do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.Context

  @derive {Inspect, only: [:invocation_id, :tool_name, :conversation_mode]}
  @enforce_keys [:invocation_id, :tool_name, :conversation_mode, :context, :outcome]
  defstruct @enforce_keys

  @type outcome :: {:ok, term()} | {:error, :invalid_result | :tool_failed | :unknown}
  @type t :: %__MODULE__{
          invocation_id: String.t(),
          tool_name: String.t(),
          conversation_mode: :blocking | :non_blocking,
          context: Context.t(),
          outcome: outcome()
        }
end
