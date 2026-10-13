defmodule Vxpipe.Identity.Accounts.NoopAudit do
  @moduledoc false
  @behaviour Vxpipe.Identity.Ports.Audit
  @impl true
  def append(_), do: :ok
end
