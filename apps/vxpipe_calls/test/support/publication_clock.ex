defmodule Vxpipe.Calls.TestPublicationClock do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationClock

  @impl true
  def now(agent), do: Agent.get(agent, & &1)
end
