defmodule Vxpipe.Identity.FakeRoles do
  @behaviour Vxpipe.Identity.Ports.Roles

  @impl true
  def fetch("role-member"), do: {:ok, %{public_id: "role-member", slug: "tenant-member", kind: :member, grants: []}}
  def fetch("role-admin"), do: {:ok, %{public_id: "role-admin", slug: "admin", kind: :admin, grants: []}}
  def fetch("role-superadmin"), do: {:ok, %{public_id: "role-superadmin", slug: "superadmin", kind: :superadmin, grants: []}}
  def fetch(_), do: {:error, :not_found}
  @impl true
  def fetch_by_slug(_), do: {:error, :not_found}
  @impl true
  def list, do: {:ok, []}
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
       |> Map.merge(%{kind: nil, revision: 1})}
    end
  end

  @impl true
  def apply_update(id, changes) do
    audit = Map.get(changes, :audit, Map.get(changes, "audit", Vxpipe.Identity.Accounts.NoopAudit))
    audit_event = Map.get(changes, :audit_event, Map.get(changes, "audit_event"))

    with :ok <- maybe_audit(audit, audit_event) do
      {:ok,
       changes
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
       |> Map.put(:public_id, id)}
    end
  end

  @impl true
  def delete(_id), do: :ok

  def delete(_id, opts) when is_map(opts) do
    audit = Map.get(opts, :audit, Vxpipe.Identity.Accounts.NoopAudit)
    audit_event = Map.get(opts, :audit_event)

    maybe_audit(audit, audit_event)
  end

  defp maybe_audit(_audit, nil), do: :ok
  defp maybe_audit(audit, event), do: audit.append(event)
  @impl true
  def count_users(_id), do: {:ok, 0}
end
