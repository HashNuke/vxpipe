import { useId } from "react";
import { canManageUser } from "./access";
import type { Role } from "./types";
export function RoleSelect({
  actor,
  roles,
  value,
  onChange,
  readOnly = false,
}: {
  actor: Role;
  roles: Role[];
  value: string;
  onChange: (value: string) => void;
  readOnly?: boolean;
}) {
  const id = useId();
  const selected = roles.find((role) => role.id === value);
  return (
    <div className="access-field">
      <label htmlFor={id}>Role</label>
      {readOnly ? (
        <p>{selected?.name ?? "Unknown role"}</p>
      ) : (
        <select
          id={id}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        >
          {roles
            .filter((role) => canManageUser(actor, role))
            .map((role) => (
              <option key={role.id} value={role.id}>
                {role.name}
              </option>
            ))}
        </select>
      )}
    </div>
  );
}
