defmodule Vxpipe.Calls.TestPublicationTimer do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationTimer

  @impl true
  def schedule(owner, token, delay_ms, observer) do
    send(observer, {:publication_timer_scheduled, owner, token, delay_ms})
    {owner, token}
  end

  @impl true
  def cancel({owner, token}, observer) do
    send(observer, {:publication_timer_cancelled, owner, token})
    :ok
  end
end
