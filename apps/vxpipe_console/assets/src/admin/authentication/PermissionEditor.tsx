import { permissionGroups } from "./access";
import type { Grant, Scope } from "./types";
export function PermissionEditor({
  value,
  onChange,
  readOnly = false,
}: {
  value: Grant[];
  onChange?: (value: Grant[]) => void;
  readOnly?: boolean;
}) {
  function includeCredentialRead(grants: Grant[]): Grant[] {
    const write = grants.find((grant) => grant.permission === "tenant_api_keys.write");
    if (!write) return grants;
    const read = grants.find((grant) => grant.permission === "tenant_services.read");
    if (!read) return [...grants, { permission: "tenant_services.read", scope: write.scope }];
    if (write.scope === "all_tenants" && read.scope !== "all_tenants") {
      return grants.map((grant) => grant === read ? { ...grant, scope: "all_tenants" } : grant);
    }
    return grants;
  }

  function changeScope(resource: string, scope: Scope, action?: "read" | "write") {
    let next = value.map((grant) =>
      grant.permission === `${resource}.${action ?? "read"}` ||
      (!action && grant.permission === `${resource}.write`)
        ? { ...grant, scope } : grant,
    );
    if (resource === "tenant_services" && action !== "write" && scope === "assigned_tenants") {
      next = next.map((grant) => grant.permission === "tenant_api_keys.write" ? { ...grant, scope } : grant);
    }
    onChange?.(includeCredentialRead(next));
  }

  function toggle(
    resource: string,
    action: "read" | "write",
    checked: boolean,
    scope: Scope,
  ) {
    let next = value.filter(
      (grant) => grant.permission !== `${resource}.${action}`,
    );
    const readResource = resource === "tenant_api_keys" ? "tenant_services" : resource;
    if (checked) {
      next.push({ permission: `${resource}.${action}`, scope });
      if (
        action === "write" &&
        !next.some((grant) => grant.permission === `${readResource}.read`)
      )
        next.push({ permission: `${readResource}.read`, scope });
    } else if (action === "read") {
      next = next.filter((grant) => grant.permission !== `${resource}.write` &&
        !(resource === "tenant_services" && grant.permission === "tenant_api_keys.write"));
    }
    onChange?.(includeCredentialRead(next));
  }
  return (
    <section className="access-section" aria-label="Role permissions">
      <h2 className="access-permissions-heading">Permissions</h2>
      <p className="access-muted">
        Choose actions, then where they apply. Write access includes read
        access.
      </p>
      <div className="access-permissions">
        {permissionGroups.map((group) => {
          const read = value.find(
            (grant) => grant.permission === `${group.resource}.read`,
          );
          const write = value.find(
            (grant) => grant.permission === `${group.resource}.write`,
          );
          const scope =
            read?.scope ??
            write?.scope ??
            (group.tenant ? "assigned_tenants" : "installation");
          return (
            <div className="access-permission-row" key={group.resource}>
              <div>
                <strong>{group.label}</strong>
                <p className="access-muted">{group.detail}</p>
              </div>
              <div className="access-permission-actions">
                {(["read", "write"] as const).map((action) => {
                  if ((action === "read" && group.writeOnly) ||
                      (action === "write" && group.readOnly)) return null;
                  const grant = action === "read" ? read : write;
                  const label = action === "read" ? "Read" : "Write";
                  const actionScope = grant?.scope ?? scope;
                  return (
                    <div className="access-permission-action" key={action}>
                      <label>
                        <input
                          type="checkbox"
                          aria-label={`${label} ${group.label}`}
                          checked={!!grant}
                          disabled={readOnly || (action === "write" && group.reservedWrite)}
                          title={action === "write" && group.reservedWrite ? "Superadmins only" : undefined}
                          onChange={(event) => toggle(group.resource, action, event.target.checked, actionScope)}
                        />
                        {label}
                      </label>
                      {group.tenant ? (
                        <select
                          aria-label={`${label} scope for ${group.label}`}
                          value={actionScope}
                          disabled={readOnly || !grant}
                          onChange={(event) => changeScope(group.resource, event.target.value as Scope, action)}
                        >
                          <option value="assigned_tenants">Assigned tenants</option>
                          <option value="all_tenants">All tenants</option>
                        </select>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
