defmodule Vxpipe.Persistence.IdentityAuditStore do
  @moduledoc "Append-only safe access-event sink. Summaries are redacted before insert."

  @behaviour Vxpipe.Identity.Ports.Audit

  import Ecto.Query

  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.Schema.UserAccessEvent

  @impl true
  def append(event) do
    Vxpipe.Persistence.IdentityRecord.insert_audit(event)
  rescue
    _ -> {:error, :unavailable}
  end

  def recent_events(limit) do
    Repo.all(from(e in UserAccessEvent, order_by: [desc: e.id], limit: ^limit))
  end
end
