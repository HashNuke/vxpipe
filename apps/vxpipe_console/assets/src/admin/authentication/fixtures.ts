import type { Role, Tenant, User } from "./types";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export const roles: Role[] = [
  {
    id: id(1),
    name: "Superadmin",
    kind: "superadmin",
    grants: [],
  },
  {
    id: id(2),
    name: "Admin",
    kind: "admin",
    grants: [],
  },
  {
    id: id(4),
    name: "Tenant Manager",
    kind: null,
    grants: [
      ...["calls.read", "calls.write", "call_specs.read", "call_specs.write", "tenant_services.read", "tenant_services.write", "tenant_api_keys.write"].map(
        (permission) => ({ permission, scope: "assigned_tenants" as const }),
      ),
      { permission: "platform_services.read", scope: "installation" },
    ],
  },
  {
    id: id(5),
    name: "Tenant Member",
    kind: null,
    grants: ["calls.read", "call_specs.read"].map((permission) => ({
      permission,
      scope: "assigned_tenants",
    })),
  },
];
export const tenants: Tenant[] = [
  { id: id(101), name: "Acme", createdAt: "2026-08-15T10:00:00Z", key: "acme_demo_000001" },
  { id: id(102), name: "Northwind", createdAt: "2026-08-15T10:00:00Z", key: "northwind_000001" },
  { id: id(103), name: "Demo workspace", createdAt: "2026-08-15T10:00:00Z", key: "demo_tenant_0001" },
  { id: id(104), name: "Contoso Support", createdAt: "2026-08-15T10:00:00Z", key: "contoso_00000001" },
  { id: id(105), name: "Fabrikam Europe", createdAt: "2026-08-15T10:00:00Z", key: "fabrikam_0000001" },
  { id: id(106), name: "Woodgrove", createdAt: "2026-08-15T10:00:00Z", key: "woodgrove_000001" },
  { id: id(107), name: "Adventure Works", createdAt: "2026-08-15T10:00:00Z", key: "adventure_000001" },
];
export const users: User[] = [
  {
    id: id(201),
    email: "owner@example.test",
    roleId: roles[0].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(202),
    email: "admin@example.test",
    roleId: roles[1].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(203),
    email: "tenant.manager@example.test",
    roleId: roles[2].id,
    enabled: true,
    memberships: [
      { tenantId: tenants[0].id, access: "read_write" },
      { tenantId: tenants[1].id, access: "read_write" },
    ],
  },
  {
    id: id(204),
    email: "operations@example.test",
    roleId: roles[2].id,
    enabled: true,
    memberships: [{ tenantId: tenants[2].id, access: "read_write" }],
  },
  {
    id: id(205),
    email: "member@example.test",
    roleId: roles[3].id,
    enabled: true,
    memberships: [
      { tenantId: tenants[0].id, access: "read" },
      { tenantId: tenants[1].id, access: "read" },
    ],
  },
  {
    id: id(206),
    email: "support.manager@example.test",
    roleId: roles[2].id,
    enabled: true,
    memberships: [
      { tenantId: tenants[0].id, access: "read" },
      { tenantId: tenants[1].id, access: "read_write" },
    ],
  },
  {
    id: id(207),
    email: "west.member@example.test",
    roleId: roles[3].id,
    enabled: true,
    memberships: [{ tenantId: tenants[3].id, access: "read" }],
  },
  {
    id: id(208),
    email: "new.member@example.test",
    roleId: roles[3].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(209),
    email: "former.member@example.test",
    roleId: roles[3].id,
    enabled: false,
    memberships: [{ tenantId: tenants[0].id, access: "read" }],
  },
];
