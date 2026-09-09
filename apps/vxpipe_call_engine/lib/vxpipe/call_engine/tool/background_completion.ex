defmodule Vxpipe.CallEngine.Tool.BackgroundCompletion do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{Call, Context}

  @enforce_keys [:call, :context, :outcome]
  defstruct @enforce_keys

  @type outcome :: {:ok, term()} | {:error, :tool_failed | :invalid_result | :unknown}

  @type t :: %__MODULE__{
          call: Call.t(),
          context: Context.t(),
          outcome: outcome()
        }
end
