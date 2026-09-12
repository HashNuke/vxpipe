defmodule Vxpipe.Calls.ProcessPublicationTimer do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationTimer

  @impl true
  def schedule(owner, token, delay_ms, _context) do
    Process.send_after(owner, {:vxpipe_publication_timer, token}, delay_ms)
  end

  @impl true
  def cancel(timer, _context) when is_reference(timer) do
    _result = Process.cancel_timer(timer)
    :ok
  end
end
