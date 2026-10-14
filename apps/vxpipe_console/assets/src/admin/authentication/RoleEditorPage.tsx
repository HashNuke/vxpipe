import { useState, type FormEvent } from "react";
import { ArrowLeft } from "lucide-react";
import { Button } from "../Button";
import { PageHeader } from "../PageHeader";
import { FormField, FormMessage } from "./FormField";
import { PermissionEditor } from "./PermissionEditor";
import { operationalGrants } from "./access";
import type { Grant, Navigate, Role, SaveResult } from "./types";
export function RoleEditorPage({
  role,
  affectedUsers = 0,
  onSave,
  onDelete,
  onNavigate,
}: {
  role?: Role;
  affectedUsers?: number;
  onSave: (
    draft: Pick<Role, "name" | "grants">,
  ) => Promise<SaveResult>;
  onDelete?: () => Promise<SaveResult>;
  onNavigate: Navigate;
}) {
  const [name, setName] = useState(role?.name ?? "");
  const [grants, setGrants] = useState<Grant[]>(
    role?.kind
      ? [
          ...operationalGrants("all_tenants"),
          ...[
            "platform_services.read",
            "platform_services.write",
            "users.read",
            "diagnostics.read",
          ].map((permission) => ({
            permission,
            scope: "installation" as const,
          })),
        ]
      : (role?.grants ?? []),
  );
  const [error, setError] = useState<string>();
  const [saved, setSaved] = useState(false);
  const [pending, setPending] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (role?.kind) return;
    setPending(true);
    try {
      const result = await onSave({
        name: name.trim(),
        grants,
      });
      setError(result.error);
      setSaved(!result.error);
    } catch {
      setError("Role could not be saved. Your edits are still here.");
    } finally {
      setPending(false);
    }
  }
  return (
    <main className="access-page access-editor">
      <a
        className="access-back"
        href="/roles"
        onClick={(event) => {
          event.preventDefault();
          onNavigate("/roles");
        }}
      >
        <ArrowLeft size={16} aria-hidden />
        Back to roles
      </a>
      <PageHeader
        title={role ? role.name : "Create role"}
        description={
          role?.kind
            ? "This built-in role has a protected permission policy."
            : "Build a role from the actions your team needs."
        }
      />
      {role?.kind ? (
        <FormMessage>
          {role.kind === "superadmin"
            ? "Can manage members, Admins and Superadmins."
            : "Can manage members. Admin and Superadmin accounts are read-only."}{" "}
          This role cannot be changed or deleted.
        </FormMessage>
      ) : null}
      <form className="access-form" onSubmit={submit}>
        <fieldset className="access-fieldset" disabled={pending}>
          <section className="access-section access-identity">
            <FormField
              label="Role name"
              required
              maxLength={80}
              value={name}
              onChange={(event) => setName(event.target.value)}
              readOnly={!!role?.kind}
            />
          </section>
          <PermissionEditor
            value={grants}
            onChange={setGrants}
            readOnly={!!role?.kind}
          />
          {!role?.kind && role ? (
            <p className="access-muted">
              Saving affects {affectedUsers}{" "}
              {affectedUsers === 1 ? "user" : "users"}. Their sessions will be
              signed out.
            </p>
          ) : null}
          {error ? <FormMessage error>{error}</FormMessage> : null}
          {saved ? <FormMessage>Role saved.</FormMessage> : null}
          {!role?.kind ? (
            <div className="access-actions">
              <Button
                type="submit"
                className="access-primary"
                disabled={pending}
              >
                {pending ? "Saving…" : role ? "Save role" : "Create role"}
              </Button>
              <Button
                type="button"
                variant="ghost"
                onClick={() => onNavigate("/roles")}
              >
                Cancel
              </Button>
            </div>
          ) : null}
        </fieldset>
      </form>
      {role && !role.kind ? (
        <section className="access-section">
          <h2>Delete role</h2>
          <p className="access-muted">
            {affectedUsers
              ? "Reassign its users before deleting this role."
              : "This role has no assigned users."}
          </p>
          {confirmDelete ? (
            <div className="access-actions">
              <Button
                type="button"
                onClick={async () => {
                  const result = await onDelete?.();
                  setError(result?.error);
                }}
              >
                Confirm delete
              </Button>
              <Button
                type="button"
                variant="ghost"
                onClick={() => setConfirmDelete(false)}
              >
                Keep role
              </Button>
            </div>
          ) : (
            <Button
              type="button"
              disabled={affectedUsers > 0}
              onClick={() => setConfirmDelete(true)}
            >
              Delete role
            </Button>
          )}
        </section>
      ) : null}
    </main>
  );
}
