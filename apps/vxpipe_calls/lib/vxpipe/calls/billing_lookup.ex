defmodule Vxpipe.Calls.BillingLookup do
  @moduledoc "Provider-neutral port for tenant-aware, out-of-room billing resolution."

  alias Vxpipe.Calls.{BillingLookupRequest, BillingLookupResult}

  @type context :: term()

  @callback lookup(context(), BillingLookupRequest.t()) ::
              {:ok, BillingLookupResult.t()}
              | {:ok, :pending}
              | {:error, term()}
end
