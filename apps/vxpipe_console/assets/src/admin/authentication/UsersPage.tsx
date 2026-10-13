import { Plus, Search } from "lucide-react";
import { Button } from "../Button";
import { Pagination } from "../Pagination";
import { PageNotice } from "../PageNotice";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../components/ui/table";
import { RoleBadge } from "./RoleBadge";
import type { Navigate, PageState, Role, User } from "./types";
export function UsersPage({
  users,
  roles,
  actorRole,
  query,
  onQuery,
  onNavigate,
  state = "ready",
  pagination,
  rolesLimited = false,
}: {
  users: User[];
  roles: Role[];
  actorRole: Role;
  query: URLSearchParams;
  onQuery: (query: URLSearchParams) => void;
  onNavigate: Navigate;
  state?: PageState;
  pagination?: { page: number; page_size: number; total: number; total_pages: number };
  /**
   * True when roles came from minimal option metadata (no grants). Tenant
   * summaries then fall back to assignment counts instead of grant analysis.
   */
  rolesLimited?: boolean;
}) {
  const search = query.get("q") ?? "";
  const roleId = query.get("role") ?? "";
  const filtered = pagination
    ? users
    : users.filter(
        (user) =>
          (!roleId || user.roleId === roleId) &&
          user.email.toLowerCase().includes(search.toLowerCase()),
      );
  const pageSize = pagination?.page_size ?? 6;
  const total = pagination?.total ?? filtered.length;
  const page = pagination?.page ?? Math.max(
    1,
    Math.min(
      Number(query.get("page")) || 1,
      Math.max(1, Math.ceil(filtered.length / pageSize)),
    ),
  );
  const shown = pagination ? filtered : filtered.slice((page - 1) * pageSize, page * pageSize);
  function filter(key: string, value: string) {
    const next = new URLSearchParams(query);
    if (value) next.set(key, value);
    else next.delete(key);
    next.delete("page");
    onQuery(next);
  }
  return (
    <main className="access-page">
      <div className="access-page-heading">
        <div><h1>Users</h1><p className="access-lead">Manage who can access your installation and its tenants.</p></div>
        {actorRole.kind ? (
          <Button
            className="access-primary"
            type="button"
            onClick={() => onNavigate("/users/new")}
          >
            <Plus size={16} aria-hidden />
            Create user
          </Button>
        ) : null}
      </div>
      <div className="access-filters">
        <label className="access-search">
          <Search size={16} aria-hidden />
          <input
            aria-label="Search users"
            type="search"
            placeholder="Search by email…"
            value={search}
            onChange={(event) => filter("q", event.target.value)}
          />
        </label>
        <label className="access-filter-label">
          Role
          <select
            aria-label="Filter by role"
            value={roleId}
            onChange={(event) => filter("role", event.target.value)}
          >
            <option value="">All roles</option>
            {roles.map((role) => (
              <option key={role.id} value={role.id}>
                {role.name}
              </option>
            ))}
          </select>
        </label>
      </div>
      {state === "loading" ? (
        <div className="access-skeleton" role="status">
          Loading users…
        </div>
      ) : state === "unavailable" ? (
        <PageNotice
          kind="unavailable"
          title="Users unavailable"
          message="The directory could not be loaded. Try again shortly."
        />
      ) : roleId && !roles.some((role) => role.id === roleId) ? (
        <PageNotice
          kind="unavailable"
          title="Unknown role filter"
          message="Choose a current role or clear the filter."
        />
      ) : filtered.length === 0 ? (
        <PageNotice
          kind="empty"
          title="No users found"
          message="Try a different email or role filter."
        />
      ) : (
        <>
          <Table className="access-directory" aria-label="Users">
            <TableHeader className="access-table-head">
              <TableRow className="access-user-row">
                <TableHead>Email</TableHead>
                <TableHead>Role</TableHead>
                <TableHead>Tenant access</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
            {shown.map((user) => {
              const role = roles.find((item) => item.id === user.roleId) ?? {
                id: user.roleId,
                name: "Unknown role",
                description: "",
                kind: null,
                grants: [],
              } as Role;
              return (
                <TableRow className="access-user-row" key={user.id}>
                  <TableCell>
                    <a
                      className="access-user-link"
                      href={`/users/${user.id}`}
                      onClick={(event) => {
                        event.preventDefault();
                        onNavigate(`/users/${user.id}`);
                      }}
                    >
                      {user.email}
                    </a>
                  </TableCell>
                  <TableCell>
                    <RoleBadge role={role} />
                  </TableCell>
                  <TableCell className="access-muted">
                    {tenantSummary(role, user, rolesLimited)}
                  </TableCell>
                  <TableCell className={user.enabled ? "access-status" : "access-muted"}>
                    {user.enabled ? "Active" : "Disabled"}
                  </TableCell>
                </TableRow>
              );
            })}
            </TableBody>
          </Table>
          <Pagination
            ariaLabel="User pages"
            pagination={{
              label: `${(page - 1) * pageSize + 1}–${Math.min(page * pageSize, total)} of ${total} users`,
              hasPrevious: page > 1,
              hasNext: page * pageSize < total,
            }}
            onPrevious={() => {
              const next = new URLSearchParams(query);
              next.set("page", String(page - 1));
              onQuery(next);
            }}
            onNext={() => {
              const next = new URLSearchParams(query);
              next.set("page", String(page + 1));
              onQuery(next);
            }}
          />
        </>
      )}
    </main>
  );
}

function tenantSummary(role: Role, user: User, rolesLimited: boolean) {
  if (rolesLimited && !role.kind) {
    return user.memberships.length > 0
      ? `${user.memberships.length} assigned`
      : "No tenant access";
  }
  const all =
    role.kind || role.grants.some((grant) => grant.scope === "all_tenants");
  const assigned = role.grants.some(
    (grant) => grant.scope === "assigned_tenants",
  );
  return all
    ? assigned
      ? `All + ${user.memberships.length} assigned`
      : "All tenants"
    : assigned
      ? `${user.memberships.length} assigned`
      : "No tenant access";
}
