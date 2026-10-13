import { roles, users } from "../authentication/fixtures";
import type { Role, User } from "../authentication/types";
export type Persona = "all" | "single" | "multiple" | "member" | "mixed" | "none" | "keys-only" | "platform-reader" | "service-reader";
export function navigationFixture(persona: Persona): { role: Role; user: User } {
  const user = persona === "single" ? users[3] : persona === "multiple" ? users[2] : persona === "none" ? users[7] : persona === "all" ? users[0] : users[4];
  const custom: Partial<Record<Persona, Role>> = {
    mixed: { ...roles[3], name: "Global call reader", grants: [{ permission: "calls.read", scope: "all_tenants" }, { permission: "tenant_services.read", scope: "assigned_tenants" }] },
    "keys-only": { ...roles[3], name: "API key reader", grants: [{ permission: "tenant_api_keys.read", scope: "assigned_tenants" }] },
    "platform-reader": { ...roles[3], name: "Platform service reader", grants: [{ permission: "platform_services.read", scope: "installation" }] },
    "service-reader": { ...roles[3], name: "Tenant service reader", grants: [{ permission: "tenant_services.read", scope: "assigned_tenants" }] },
  };
  return { user, role: custom[persona] ?? roles.find(item => item.id === user.roleId)! };
}
