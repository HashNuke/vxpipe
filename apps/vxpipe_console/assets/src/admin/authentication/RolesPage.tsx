import { Plus, ChevronRight } from "lucide-react";
import { Button } from "../Button";
import { PageHeader } from "../PageHeader";
import { RoleBadge } from "./RoleBadge";
import type { Navigate, Role, User } from "./types";
export function RolesPage({
  roles,
  users,
  onNavigate,
}: {
  roles: Role[];
  users: User[];
  onNavigate: Navigate;
}) {
  return (
    <main className="access-page">
      <div className="access-page-heading">
        <PageHeader
          title="Roles"
          description="Define what people can do. Assign tenants on each user's account."
        />
        <Button
          className="access-primary"
          onClick={() => onNavigate("/admin/roles/new")}
        >
          <Plus size={16} aria-hidden />
          Create role
        </Button>
      </div>
      <div className="access-role-list">
        {roles.map((role) => (
          <a
            key={role.id}
            href={`#/admin/roles/${role.id}`}
            onClick={(event) => {
              event.preventDefault();
              onNavigate(`/admin/roles/${role.id}`);
            }}
          >
            <div>
              <RoleBadge role={role} />
              <p className="access-muted">{role.description}</p>
            </div>
            <span className="access-muted">
              Users: {users.filter((user) => user.roleId === role.id).length}
            </span>
            <span className="access-role-kind">
              {role.kind ? "Built-in · protected" : "Custom role"}
            </span>
            <ChevronRight size={16} aria-hidden />
          </a>
        ))}
      </div>
    </main>
  );
}
