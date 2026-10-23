import { Pagination } from "../Pagination";
import { Plus, ChevronRight } from "lucide-react";
import { Button } from "../Button";
import { RoleBadge } from "./RoleBadge";
import type { Navigate, Role } from "./types";
export function RolesPage({
  roles,
  affectedUsers,
  onNavigate,
  pagination,
  onPage,
}: {
  roles: Role[];
  /**
   * Authoritative per-role user counts from GET /api/roles/:id. Roles
   * missing from the map render a non-authoritative placeholder instead of
   * a partial-directory count.
   */
  affectedUsers: Record<string, number>;
  onNavigate: Navigate;
  pagination?: { page: number; page_size: number; total: number; total_pages: number };
  onPage?: (page: number) => void;
}) {
  return (
    <main className="access-page">
      <div className="access-page-heading">
        <div><h1>Roles</h1></div>
        <Button
          className="access-primary"
          onClick={() => onNavigate("/roles/new")}
        >
          <Plus size={16} aria-hidden />
          Create role
        </Button>
      </div>
      <div className="access-role-list">
        {roles.map((role) => {
          const count = affectedUsers[role.id];
          return (
          <a
            key={role.id}
            href={`/roles/${role.id}`}
            onClick={(event) => {
              event.preventDefault();
              onNavigate(`/roles/${role.id}`);
            }}
          >
            <div>
              <RoleBadge role={role} />
            </div>
            <span className="access-muted">
              {typeof count === "number" ? `Users: ${count}` : "Users: see details"}
            </span>
            <span className="access-role-kind">
              {role.kind ? "Built-in · protected" : "Custom role"}
            </span>
            <ChevronRight size={16} aria-hidden />
          </a>
          );
        })}
      </div>
      {pagination ? (
        <Pagination
          ariaLabel="Role pagination"
          pagination={{
            hasPrevious: pagination.page > 1,
            hasNext: pagination.page < pagination.total_pages,
            label: `${pagination.total} roles · Page ${pagination.page} of ${Math.max(1, pagination.total_pages)}`,
          }}
          onPrevious={() => onPage?.(pagination.page - 1)}
          onNext={() => onPage?.(pagination.page + 1)}
        />
      ) : null}
    </main>
  );
}
