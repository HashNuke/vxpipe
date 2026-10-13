import { Plus, Search } from "lucide-react";
import { Button } from "../Button";
import { PageHeader } from "../PageHeader";
import { Pagination } from "../Pagination";
import { PageNotice } from "../PageNotice";
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
}: {
  users: User[];
  roles: Role[];
  actorRole: Role;
  query: URLSearchParams;
  onQuery: (query: URLSearchParams) => void;
  onNavigate: Navigate;
  state?: PageState;
}) {
  const search = query.get("q") ?? "";
  const roleId = query.get("role") ?? "";
  const filtered = users.filter(
    (user) =>
      (!roleId || user.roleId === roleId) &&
      user.email.toLowerCase().includes(search.toLowerCase()),
  );
  const page = Math.max(
    1,
    Math.min(
      Number(query.get("page")) || 1,
      Math.max(1, Math.ceil(filtered.length / 6)),
    ),
  );
  const shown = filtered.slice((page - 1) * 6, page * 6);
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
        <PageHeader
          title="Users"
          description="Manage who can access your installation and its tenants."
        />
        {actorRole.kind ? (
          <Button
            className="access-primary"
            type="button"
            onClick={() => onNavigate("/admin/users/new")}
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
          <div className="access-directory" role="table" aria-label="Users">
            <div className="access-user-row access-table-head" role="row">
              <span role="columnheader">Email</span>
              <span role="columnheader">Role</span>
              <span role="columnheader">Tenant access</span>
              <span role="columnheader">Status</span>
            </div>
            {shown.map((user) => {
              const role = roles.find((item) => item.id === user.roleId)!;
              const all =
                role.kind ||
                role.grants.some((grant) => grant.scope === "all_tenants");
              const assigned = role.grants.some(
                (grant) => grant.scope === "assigned_tenants",
              );
              return (
                <div className="access-user-row" role="row" key={user.id}>
                  <span role="cell">
                    <a
                      className="access-user-link"
                      href={`#/admin/users/${user.id}`}
                      onClick={(event) => {
                        event.preventDefault();
                        onNavigate(`/admin/users/${user.id}`);
                      }}
                    >
                      {user.email}
                    </a>
                  </span>
                  <span role="cell">
                    <RoleBadge role={role} />
                  </span>
                  <span role="cell" className="access-muted">
                    {all
                      ? assigned
                        ? `All + ${user.memberships.length} assigned`
                        : "All tenants"
                      : assigned
                        ? `${user.memberships.length} assigned`
                        : "No tenant access"}
                  </span>
                  <span
                    role="cell"
                    className={user.enabled ? "access-status" : "access-muted"}
                  >
                    {user.enabled ? "Active" : "Disabled"}
                  </span>
                </div>
              );
            })}
          </div>
          <Pagination
            ariaLabel="User pages"
            pagination={{
              label: `${(page - 1) * 6 + 1}–${Math.min(page * 6, filtered.length)} of ${filtered.length} users`,
              hasPrevious: page > 1,
              hasNext: page * 6 < filtered.length,
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
