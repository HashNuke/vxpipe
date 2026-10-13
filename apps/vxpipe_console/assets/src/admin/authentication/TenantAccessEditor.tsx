import { useState } from "react";
import { Plus, Search, X, Globe2 } from "lucide-react";
import { Button } from "../Button";
import { effectiveAccess, hasAssignedGrants } from "./access";
import type { Membership, Role, Tenant } from "./types";
const label = (access: string) =>
  access === "write" ? "read & write" : access === "read" ? "read" : "none";
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
  const assigned = hasAssignedGrants(role);
  const all =
    role.kind || role.grants.some((grant) => grant.scope === "all_tenants");
  const write = role.grants.some(
    (grant) =>
      grant.scope === "assigned_tenants" && grant.permission.endsWith(".write"),
  );
  const matches = tenants.filter((tenant) =>
    `${tenant.name} ${tenant.key}`.toLowerCase().includes(search.toLowerCase()),
  );
  const summary = (access?: Membership["access"]) =>
    `Calls: ${label(effectiveAccess(role, "calls", access))} · Call specs: ${label(effectiveAccess(role, "call_specs", access))}`;
  return (
    <section className="access-section" aria-label="Tenant access">
      <div className="access-section-heading">
        <div>
          <h2>Tenant access</h2>
          <p className="access-muted">
            The role defines available actions. Assignments define where they
            apply.
          </p>
        </div>
        {assigned && !readOnly ? (
          <Button
            type="button"
            onClick={() => setOpen(!open)}
            aria-expanded={open}
          >
            <Plus size={15} aria-hidden />
            Add tenants
          </Button>
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
      {assigned && open && !readOnly ? (
        <div className="access-picker">
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
              const selected = value.some(
                (item) => item.tenantId === tenant.id,
              );
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
                  <span>
                    {tenant.name}
                    <small>{tenant.key}</small>
                  </span>
                </label>
              );
            })}
            {matches.length === 0 ? (
              <p className="access-empty">No tenants match your search.</p>
            ) : null}
          </div>
          <div className="access-picker-footer">
            <span className="access-muted">{value.length} selected</span>
            <Button type="button" onClick={() => setOpen(false)}>
              Done
            </Button>
          </div>
        </div>
      ) : null}
      {assigned && value.length === 0 ? (
        <div className="access-empty">
          <strong>No tenants assigned</strong>
          <p className="access-muted">
            {all
              ? "Only the all-tenant permissions above apply."
              : "Add tenants to give this user access to calls and call specs."}
          </p>
        </div>
      ) : null}
      {assigned &&
        value.map((membership) => {
          const tenant = tenants.find(
            (item) => item.id === membership.tenantId,
          );
          return (
            <div className="access-tenant-row" key={membership.tenantId}>
              <div>
                <strong>{tenant?.name ?? "Unavailable tenant"}</strong>
                <small className="access-key">
                  {tenant?.key ?? membership.tenantId}
                </small>
                <p className="access-muted">{summary(membership.access)}</p>
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
  );
}
