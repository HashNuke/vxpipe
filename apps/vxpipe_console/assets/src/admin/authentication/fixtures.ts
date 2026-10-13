import { operationalGrants } from "./access";
import type { Role, Tenant, User } from "./types";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export const roles: Role[] = [
  {
    id: id(1),
    name: "Superadmin",
    description: "Full operational access and management of every account.",
    kind: "superadmin",
    grants: [],
  },
  {
    id: id(2),
    name: "Admin",
    description: "Full operational access. Manages member accounts only.",
    kind: "admin",
    grants: [],
  },
  {
    id: id(3),
    name: "Platform Manager",
    description: "Manages services, calls and call specs across all tenants.",
    kind: null,
    grants: [
      ...operationalGrants("all_tenants"),
      { permission: "platform_services.read", scope: "installation" },
      { permission: "platform_services.write", scope: "installation" },
      { permission: "call_specs.use_platform_services", scope: "all_tenants" },
    ],
  },
  {
    id: id(4),
    name: "Tenant Manager",
    description: "Manages all tenants and reads platform service metadata.",
    kind: null,
    grants: [
      ...operationalGrants("all_tenants"),
      { permission: "platform_services.read", scope: "installation" },
      { permission: "call_specs.use_platform_services", scope: "all_tenants" },
    ],
  },
  {
    id: id(5),
    name: "Tenant Member",
    description: "Calls and call specs in assigned tenants only.",
    kind: null,
    grants: [
      "calls.read",
      "calls.write",
      "call_specs.read",
      "call_specs.write",
    ].map((permission) => ({ permission, scope: "assigned_tenants" })),
  },
  {
    id: id(6),
    name: "Call Reviewer",
    description:
      "Reads calls across all tenants and specs in assigned tenants.",
    kind: null,
    grants: [
      { permission: "calls.read", scope: "all_tenants" },
      { permission: "call_specs.read", scope: "assigned_tenants" },
    ],
  },
  {
    id: id(7),
    name: "Directory Reader",
    description: "Reads the user directory without managing accounts.",
    kind: null,
    grants: [{ permission: "users.read", scope: "installation" }],
  },
];
export const tenants: Tenant[] = [
  { id: id(101), name: "Acme", key: "acme_demo_000001" },
  { id: id(102), name: "Northwind", key: "northwind_000001" },
  { id: id(103), name: "Demo workspace", key: "demo_tenant_0001" },
  { id: id(104), name: "Contoso Support", key: "contoso_00000001" },
  { id: id(105), name: "Fabrikam Europe", key: "fabrikam_0000001" },
  { id: id(106), name: "Woodgrove", key: "woodgrove_000001" },
  { id: id(107), name: "Adventure Works", key: "adventure_000001" },
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
    email: "platform@example.test",
    roleId: roles[2].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(204),
    email: "operations@example.test",
    roleId: roles[3].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(205),
    email: "member@example.test",
    roleId: roles[4].id,
    enabled: true,
    memberships: [
      { tenantId: tenants[0].id, access: "read" },
      { tenantId: tenants[1].id, access: "read_write" },
    ],
  },
  {
    id: id(206),
    email: "reviewer@example.test",
    roleId: roles[5].id,
    enabled: true,
    memberships: [{ tenantId: tenants[0].id, access: "read" }],
  },
  {
    id: id(207),
    email: "directory@example.test",
    roleId: roles[6].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(208),
    email: "new.member@example.test",
    roleId: roles[4].id,
    enabled: true,
    memberships: [],
  },
  {
    id: id(209),
    email: "former.member@example.test",
    roleId: roles[4].id,
    enabled: false,
    memberships: [{ tenantId: tenants[0].id, access: "read" }],
  },
];
