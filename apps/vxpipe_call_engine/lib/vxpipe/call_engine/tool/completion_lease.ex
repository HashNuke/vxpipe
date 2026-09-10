defmodule Vxpipe.CallEngine.Tool.CompletionLease do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.InvocationCompletion

  @derive {Inspect, only: [:invocation_id, :consumer_id]}
  @enforce_keys [:invocation_id, :consumer_id, :lease_id, :completion]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          invocation_id: String.t(),
          consumer_id: String.t(),
          lease_id: reference(),
          completion: InvocationCompletion.t()
        }
end
