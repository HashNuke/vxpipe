defmodule Vxpipe.Calls.SystemPublicationClock do
  @moduledoc false

  @behaviour Vxpipe.Calls.PublicationClock

  @impl true
  def now(_context), do: DateTime.utc_now(:millisecond)
end
