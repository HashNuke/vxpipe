import { useState } from "react";
import { AccessFrame } from "./AccessFrame";
import { PasswordFields } from "./PasswordFields";
import { RoleBadge } from "./RoleBadge";
import { RoleSelect } from "./RoleSelect";
import { TenantAccessEditor } from "./TenantAccessEditor";
import { PermissionEditor } from "./PermissionEditor";
import { roles, tenants, users } from "./fixtures";
import type { Grant, Membership, Theme } from "./types";
export function ComponentExamples({
  component,
  theme = "dark",
  variant = "default",
}: {
  component:
    "passwords" | "badges" | "role-select" | "tenant-access" | "permissions";
  theme?: Theme;
  variant?:
    | "default"
    | "empty"
    | "all-tenants"
    | "mixed"
    | "mixed-scopes"
    | "read-only"
    | "admin";
}) {
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [roleId, setRoleId] = useState(roles[2].id);
  const [assignments, setAssignments] = useState<Membership[]>(
    variant === "empty" ? [] : users[5].memberships,
  );
  const mixedScopeGrants: Grant[] = [
    { permission: "calls.read", scope: "all_tenants" },
    { permission: "calls.write", scope: "assigned_tenants" },
    { permission: "call_specs.read", scope: "assigned_tenants" },
    { permission: "call_specs.write", scope: "assigned_tenants" },
  ];
  const [grants, setGrants] = useState<Grant[]>(
    variant === "empty" ? [] : variant === "mixed-scopes" ? mixedScopeGrants : roles[2].grants,
  );
  return (
    <AccessFrame theme={theme}>
      <main className="access-component">
        {component === "passwords" ? (
          <PasswordFields
            password={password}
            confirmation={confirmation}
            onPassword={setPassword}
            onConfirmation={setConfirmation}
          />
        ) : component === "badges" ? (
          <div className="flex flex-col items-start gap-4">
            {roles.map((role) => (
              <RoleBadge role={role} key={role.id} />
            ))}
          </div>
        ) : component === "role-select" ? (
          <RoleSelect
            actor={variant === "admin" ? roles[1] : roles[0]}
            roles={roles}
            value={roleId}
            onChange={setRoleId}
            readOnly={variant === "read-only"}
          />
        ) : component === "tenant-access" ? (
          <TenantAccessEditor
            role={
              variant === "all-tenants"
                ? roles[1]
                : variant === "mixed"
                  ? { ...roles[2], grants: mixedScopeGrants }
                  : variant === "read-only"
                    ? roles[3]
                    : roles[2]
            }
            tenants={tenants}
            value={assignments}
            onChange={setAssignments}
            readOnly={variant === "read-only"}
          />
        ) : (
          <PermissionEditor
            value={grants}
            onChange={setGrants}
            readOnly={variant === "read-only"}
          />
        )}
      </main>
    </AccessFrame>
  );
}
