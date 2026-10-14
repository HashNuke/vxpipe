import { useState } from "react";
import { Plus, Search, X, Globe2 } from "lucide-react";
import { Button } from "../Button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "../components/ui/dialog";
import { effectiveAccess, hasAssignedGrants } from "./access";
import type { Membership, Role, Tenant } from "./types";
export function TenantAccessEditor({
  role,
  tenants,
  value,
  onChange,
  readOnly = false,
}: {
  role: Role;
  tenants: Tenant[];
  value: Membership[];
  onChange?: (value: Membership[]) => void;
  readOnly?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [portalContainer, setPortalContainer] = useState<HTMLElement | null>(null);
  const assigned = hasAssignedGrants(role);
  // Minimal option metadata carries no grants. Read-only viewers still need
  // to see the stored assignments; show the assignment level instead of a
  // grant-derived summary the client cannot compute.
  const unknownGrants = !role.kind && role.grants.length === 0;
  const all =
    role.kind || role.grants.some((grant) => grant.scope === "all_tenants");
  const write =
    role.grants.some(
      (grant) =>
        grant.scope === "assigned_tenants" &&
        grant.permission.endsWith(".write"),
    );
  const matches = tenants.filter((tenant) =>
    `${tenant.name} ${tenant.key}`.toLowerCase().includes(search.toLowerCase()),
  );
  const summary = (access?: Membership["access"]) => {
    const resources = [["calls", "calls"], ["call_specs", "Call Specs"], ["tenant_services", "Services"], ["tenant_api_keys", "provider credentials"], ["access_keys", "API keys"]];
    return resources.flatMap(([resource, name]) => {
      const level = effectiveAccess(role, resource, access);
      if (resource === "tenant_api_keys") return level === "write" ? ["Write provider credentials"] : [];
      return level === "none" ? [] : [`${level === "write" ? "Read and write" : "Read"} ${name}`];
    }).join(", ") || "No tenant permissions";
  };
  return (
    <Dialog open={open} onOpenChange={setOpen}>
    <section className="access-section" aria-label="Tenant access" ref={setPortalContainer}>
      <div className="access-section-heading">
        <div>
          <h2>Tenant access</h2>
        </div>
        {assigned && !readOnly ? (
          <DialogTrigger asChild>
            <Button type="button">
              <Plus size={15} aria-hidden />
              Add tenants
            </Button>
          </DialogTrigger>
        ) : null}
      </div>
      {all ? (
        <div className="access-inherited">
          <Globe2 size={18} aria-hidden />
          <div>
            <strong>All tenants — granted by role</strong>
            <p className="access-muted">
              {summary()}. Includes tenants created later.
            </p>
          </div>
        </div>
      ) : null}
      {!assigned && !all ? (
        <p className="access-empty">This role has no tenant access.</p>
      ) : null}
      {assigned && value.length === 0 ? (
        <div className="access-empty">
          <strong>No tenants assigned</strong>
          <p className="access-muted">
            {all
              ? "Only the all-tenant permissions above apply."
              : "Add tenants to give this user access to tenant operations."}
          </p>
        </div>
      ) : null}
      {(assigned || readOnly) &&
        value.map((membership) => {
          const tenant = tenants.find(
            (item) => item.id === membership.tenantId,
          );
          return (
            <div className="access-tenant-row" key={membership.tenantId}>
              <div>
                <strong>{tenant?.name ?? "Unavailable tenant"}</strong>
                <p className="access-muted">
                  {readOnly && unknownGrants
                    ? membership.access === "read"
                      ? "Read only assignment"
                      : "Read & write assignment"
                    : summary(membership.access)}
                </p>
              </div>
              <div className="access-tenant-actions">
                {readOnly ? (
                  <span>
                    {membership.access === "read"
                      ? "Read only"
                      : "Read & write"}
                  </span>
                ) : (
                  <>
                    <select
                      aria-label={`Access for ${tenant?.name}`}
                      value={write ? membership.access : "read"}
                      onChange={(event) =>
                        onChange?.(
                          value.map((item) =>
                            item.tenantId === membership.tenantId
                              ? {
                                  ...item,
                                  access: event.target
                                    .value as Membership["access"],
                                }
                              : item,
                          ),
                        )
                      }
                    >
                      <option value="read">Read only</option>
                      {write ? (
                        <option value="read_write">Read & write</option>
                      ) : null}
                    </select>
                    <Button
                      type="button"
                      variant="ghost"
                      aria-label={`Remove ${tenant?.name}`}
                      onClick={() =>
                        onChange?.(
                          value.filter(
                            (item) => item.tenantId !== membership.tenantId,
                          ),
                        )
                      }
                    >
                      <X size={16} aria-hidden />
                    </Button>
                  </>
                )}
              </div>
            </div>
          );
        })}
    </section>
    {assigned && !readOnly ? (
      <DialogContent container={portalContainer ?? undefined} className="access-tenant-dialog">
        <DialogHeader>
          <DialogTitle>Add tenants</DialogTitle>
          <DialogDescription>Choose the tenants this user can access. You can change each assignment on the form.</DialogDescription>
        </DialogHeader>
        <label className="access-search">
          <Search size={16} aria-hidden />
          <input
            type="search"
            aria-label="Search tenants"
            placeholder="Search tenants by name or key…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        </label>
        <div className="access-picker-options">
          {matches.map((tenant) => {
            const selected = value.some((item) => item.tenantId === tenant.id);
            return (
              <label key={tenant.id} className="access-pick-row">
                <input
                  type="checkbox"
                  checked={selected}
                  onChange={() =>
                    onChange?.(
                      selected
                        ? value.filter((item) => item.tenantId !== tenant.id)
                        : [...value, { tenantId: tenant.id, access: "read" }],
                    )
                  }
                />
                <span>{tenant.name}</span>
              </label>
            );
          })}
          {matches.length === 0 ? <p className="access-empty">No tenants match your search.</p> : null}
        </div>
        <DialogFooter className="access-picker-footer">
          <span className="access-muted">{value.length} selected</span>
          <Button type="button" onClick={() => setOpen(false)}>Done</Button>
        </DialogFooter>
      </DialogContent>
    ) : null}
    </Dialog>
  );
}
