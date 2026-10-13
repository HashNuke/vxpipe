import { LockKeyhole } from "lucide-react";
import type { Role } from "./types";
export function RoleBadge({ role }: { role: Role }) {
  return (
    <span className="access-role">
      {role.kind ? <LockKeyhole size={13} aria-hidden /> : null}
      {role.name}
    </span>
  );
}
