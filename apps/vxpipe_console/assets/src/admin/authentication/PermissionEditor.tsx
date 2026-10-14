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
    if (!next.some((grant) => grant.permission === "call_specs.write"))
      next = next.filter(
        (grant) => grant.permission !== "call_specs.use_platform_services",
      );
    onChange?.(includeCredentialRead(next));
  }
  return (
    <section className="access-section" aria-label="Role permissions">
      <h2>Permissions</h2>
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
          // Read and write grants carry independent scopes (for example
          // all-tenant read with assigned-tenant write). A single selector
          // must not collapse them into one scope.
          const independentScopes =
            group.tenant && !!read && !!write;
          return (
            <div className="access-permission-row" key={group.resource}>
              <div>
                <strong>{group.label}</strong>
                <p className="access-muted">{group.detail}</p>
              </div>
              <div className={`access-grants${group.writeOnly ? " access-grants-write-only" : ""}`}>
                {!group.writeOnly ? <label>
                  <input
                    type="checkbox"
                    aria-label={`Read ${group.label}`}
                    checked={!!read}
                    disabled={readOnly}
                    onChange={(event) =>
                      toggle(
                        group.resource,
                        "read",
                        event.target.checked,
                        scope,
                      )
                    }
                  />
                  Read
                </label> : null}
                {!group.readOnly ? (
                  <label>
                    <input
                      type="checkbox"
                      aria-label={`Write ${group.label}`}
                      checked={!!write}
                      disabled={readOnly}
                      onChange={(event) =>
                        toggle(
                          group.resource,
                          "write",
                          event.target.checked,
                          scope,
                        )
                      }
                    />
                    Write
                  </label>
                ) : (
                  <span className="access-muted">Read only</span>
                )}
              </div>
              {group.tenant ? (
                independentScopes ? (
                  <>
                    <select
                      aria-label={`Read scope for ${group.label}`}
                      value={read.scope}
                      disabled={readOnly}
                      onChange={(event) =>
                        changeScope(
                          group.resource,
                          event.target.value as Scope, "read",
                        )
                      }
                    >
                      <option value="assigned_tenants">Read: Assigned tenants</option>
                      <option value="all_tenants">Read: All tenants</option>
                    </select>
                    <select
                      aria-label={`Write scope for ${group.label}`}
                      value={write.scope}
                      disabled={readOnly}
                      onChange={(event) =>
                        changeScope(
                          group.resource,
                          event.target.value as Scope, "write",
                        )
                      }
                    >
                      <option value="assigned_tenants">Write: Assigned tenants</option>
                      <option value="all_tenants">Write: All tenants</option>
                    </select>
                  </>
                ) : (
                <select
                  aria-label={`Scope for ${group.label}`}
                  value={scope}
                  disabled={readOnly || (!read && !write)}
                  onChange={(event) =>
                    changeScope(group.resource, event.target.value as Scope)
                  }
                >
                  <option value="assigned_tenants">Assigned tenants</option>
                  <option value="all_tenants">All tenants</option>
                </select>
                )
              ) : (
                <span className="access-muted">Installation</span>
              )}
            </div>
          );
        })}
      </div>
      <label className="access-check">
        <input
          type="checkbox"
          checked={value.some(
            (grant) => grant.permission === "call_specs.use_platform_services",
          )}
          disabled={
            readOnly ||
            !value.some((grant) => grant.permission === "call_specs.write")
          }
          onChange={(event) =>
            onChange?.([
              ...value.filter(
                (grant) =>
                  grant.permission !== "call_specs.use_platform_services",
              ),
              ...(event.target.checked
                ? [
                    {
                      permission: "call_specs.use_platform_services",
                      scope: "installation" as const,
                    },
                  ]
                : []),
            ])
          }
        />
        Allow platform services in call specs
      </label>
    </section>
  );
}
