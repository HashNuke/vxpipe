defmodule Vxpipe.CallEngine.CallLifecycle.ProcessTimer do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.CallLifecycle.Timer

  @impl true
  def schedule(owner, token, event, timeout_ms, _options) do
    Process.send_after(
      owner,
      {:vxpipe_call_lifecycle_timer, token, event},
      timeout_ms
    )
  end

  @impl true
  def cancel(handle, _options) do
    _ = Process.cancel_timer(handle, async: true, info: false)
    :ok
  end
end
