defmodule Vxpipe.Calls.OperatorCallContext do
  @moduledoc "Tenant and call metadata for an installation-operator call-details page."

  alias Vxpipe.Calls.{CallDirectorySummary, Tenant}

  @enforce_keys [:tenant, :call]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant: Tenant.t(),
          call: CallDirectorySummary.t()
        }
end
