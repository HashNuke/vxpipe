export type Theme = "dark" | "light";
export type SystemKind = "superadmin" | "admin" | null;
export type Scope = "installation" | "all_tenants" | "assigned_tenants";
export type AccessLevel = "read" | "read_write";
export type Grant = { permission: string; scope: Scope };
export type Role = {
  id: string;
  name: string;
  kind: SystemKind;
  grants: Grant[];
  /** Server revision for optimistic role updates; absent on minimal option metadata. */
  revision?: number;
};
export type Tenant = { id: string; name: string; key: string; createdAt?: string };
export type Membership = { tenantId: string; access: AccessLevel };
export type User = {
  id: string;
  email: string;
  roleId: string;
  enabled: boolean;
  memberships: Membership[];
};
export type Navigate = (path: string) => void;
export type SaveResult = { error?: string };
export type PageState = "ready" | "loading" | "unavailable";
