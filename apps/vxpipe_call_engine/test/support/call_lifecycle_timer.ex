defmodule Vxpipe.CallEngine.TestCallLifecycleTimer do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.CallLifecycle.Timer

  @impl true
  def schedule(owner, token, event, timeout_ms, options)
      when is_pid(owner) and is_reference(token) and is_atom(event) and is_integer(timeout_ms) do
    observer = Keyword.fetch!(options, :observer)
    handle = {owner, token, event}
    send(observer, {:test_call_lifecycle_timer_scheduled, handle, timeout_ms})
    handle
  end

  @impl true
  def cancel({_owner, _token, _event} = handle, options) do
    send(Keyword.fetch!(options, :observer), {:test_call_lifecycle_timer_cancelled, handle})
    :ok
  end

  def fire({owner, token, event}) do
    send(owner, {:vxpipe_call_lifecycle_timer, token, event})
    :ok
  end
end
