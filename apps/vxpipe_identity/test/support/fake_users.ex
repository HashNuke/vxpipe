defmodule Vxpipe.Identity.FakeUsers do
  @behaviour Vxpipe.Identity.Ports.Users

  def start_link(initial \\ %{}) do
    Agent.start_link(fn -> initial end)
  end

  @impl true
  def fetch_by_email(_email), do: {:error, :not_found}
  @impl true
  def fetch_by_public_id(_id), do: {:error, :not_found}
  @impl true
  def create(attrs) do
    audit = Map.get(attrs, :audit, Map.get(attrs, "audit", Vxpipe.Identity.Accounts.NoopAudit))
    audit_event = Map.get(attrs, :audit_event, Map.get(attrs, "audit_event"))

    with :ok <- maybe_audit(audit, audit_event) do
      {:ok,
       attrs
       |> Map.drop([
         :audit,
         :audit_event,
         "audit",
         "audit_event",
         :actor_user_public_id,
         :actor_session_public_id,
         "actor_user_public_id",
         "actor_session_public_id"
       ])
       |> Map.put(:disabled_at, nil)}
    end
  end

  @impl true
  def apply_update(_id, changes) do
    audit = Map.get(changes, :audit, Map.get(changes, "audit", Vxpipe.Identity.Accounts.NoopAudit))
    audit_event = Map.get(changes, :audit_event, Map.get(changes, "audit_event"))

    with :ok <- maybe_audit(audit, audit_event) do
      {:error, :not_found}
    end
  end

  defp maybe_audit(_audit, nil), do: :ok
  defp maybe_audit(audit, event), do: audit.append(event)
  @impl true
  def list(_filters), do: {:ok, %{users: [], total: 0}}
  @impl true
  def count_enabled_superadmins, do: {:ok, 1}
end
