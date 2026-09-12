defmodule Vxpipe.Persistence.TestBillingLookup do
  @behaviour Vxpipe.Calls.BillingLookup

  @impl true
  def lookup(context, request) do
    send(context.owner, {:billing_lookup_started, self(), request})

    receive do
      {:release_billing_lookup, release_ref} when release_ref == context.release_ref ->
        context.response
    end
  end
end
