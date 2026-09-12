defmodule Vxpipe.Calls.TestBillingLookup do
  @behaviour Vxpipe.Calls.BillingLookup

  @impl true
  def lookup(context, request) do
    send(context.owner, {:billing_lookup_started, self(), request})
    await_release(context)
    respond(context.response, request)
  end

  defp await_release(%{release_ref: release_ref}) do
    receive do
      {:release_billing_lookup, ^release_ref} -> :ok
    end
  end

  defp await_release(_context), do: :ok

  defp respond(response, request) when is_function(response, 1), do: response.(request)
  defp respond(response, _request), do: response
end
