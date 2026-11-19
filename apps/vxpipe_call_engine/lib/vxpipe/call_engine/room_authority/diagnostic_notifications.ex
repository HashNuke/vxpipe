defmodule Vxpipe.CallEngine.RoomAuthority.DiagnosticNotifications do
  @moduledoc false
  alias Vxpipe.CallEngine.Diagnostics.RoomService

  # Hints never wait for diagnostics. Authoritative source reads happen after the
  # room callback installs its new state; shutdown is handled by room monitoring.
  def notify({:reply, reply, state}) do
    RoomService.notify_room(state.snapshot)
    {:reply, reply, state}
  end

  def notify({:noreply, state}) do
    RoomService.notify_room(state.snapshot)
    {:noreply, state}
  end

  def notify(other), do: other
end
