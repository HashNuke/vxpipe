import { StoryNavigationContext } from "../stories/storyNavigation";
import { useEffect, useRef, useContext, useState, type FormEvent } from "react";
import { ArrowLeft, KeyRound } from "lucide-react";
import { Button } from "../Button";
import { PageHeader } from "../PageHeader";
import { canManageUser, hasAssignedGrants, validatePassword } from "./access";
import { FormField, FormMessage } from "./FormField";
import { PasswordFields } from "./PasswordFields";
import { RoleSelect } from "./RoleSelect";
import { TenantAccessEditor } from "./TenantAccessEditor";
import type {
  Membership,
  Navigate,
  Role,
  SaveResult,
  Tenant,
  User,
} from "./types";
export type UserDraft = Omit<User, "id">;
export function UserEditorPage({
  actorRole,
  roles,
  tenants,
  user,
  onSave,
  onNavigate,
  loadRole,
}: {
  actorRole: Role;
  roles: Role[];
  tenants: Tenant[];
  user?: User;
  onSave: (draft: UserDraft, password?: string) => Promise<SaveResult>;
  onNavigate: Navigate;
  loadRole?: (id: string) => Promise<Role | null>;
}) {
  const storyNavigation = useContext(StoryNavigationContext);
  const [email, setEmail] = useState(user?.email ?? "");
  const [roleId, setRoleId] = useState(
    user?.roleId ?? roles.find((role) => hasAssignedGrants(role))?.id ?? roles.find((role) => !role.kind)?.id ?? roles.find((role) => canManageUser(actorRole, role))?.id ?? "",
  );
  const [memberships, setMemberships] = useState<Membership[]>(
    user?.memberships ?? [],
  );
  const [enabled, setEnabled] = useState(user?.enabled ?? true);
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [pending, setPending] = useState(false);
  const [roleRead, setRoleRead] = useState<{
    id: string;
    phase: "loading" | "ready" | "unavailable";
    role: Role | null;
  }>({ id: roleId, phase: loadRole ? "loading" : "ready", role: null });
  const [roleRetry, setRoleRetry] = useState(0);
  const successfulRole = useRef(roleId);
  useEffect(() => {
    if (!loadRole) return;
    let active = true;
    loadRole(roleId).then((detail) => {
      if (!active) return;
      if (detail && detail.id !== roleId) throw new Error("Invalid role response");
      if (detail && successfulRole.current !== roleId) {
        setMemberships(roleId === user?.roleId ? user.memberships : []);
      }
      successfulRole.current = roleId;
      setRoleRead({ id: roleId, phase: "ready", role: detail });
    }).catch(() => {
      if (active) setRoleRead({ id: roleId, phase: "unavailable", role: null });
    });
    return () => { active = false; };
  }, [loadRole, roleId, roleRetry, user]);
  const currentRead = roleRead.id === roleId ? roleRead : null;
  const roleReady = !loadRole || currentRead?.phase === "ready";
  const limitedRole = !!loadRole && !currentRead?.role;
  const role = currentRead?.role ?? roles.find((item) => item.id === roleId);
  const original = roles.find((item) => item.id === user?.roleId) ?? role;
  const editable = !!role && !!original && canManageUser(actorRole, original, role);
  async function submit(event: FormEvent) {
    event.preventDefault();
    setNotice(undefined);
    if (!editable || !role || !roleReady) return;
    const problem = !user
      ? validatePassword(password, confirmation)
      : undefined;
    if (problem) {
      setError(problem);
      return;
    }
    setPending(true);
    try {
      const result = await onSave(
        {
          email: email.trim(),
          roleId,
          enabled,
          memberships: limitedRole ? user?.memberships ?? [] : hasAssignedGrants(role) ? memberships : [],
        },
        user ? undefined : password,
      );
      setError(result.error);
      if (!result.error)
        setNotice("Changes saved. Updated access applies on the next sign-in.");
    } catch {
      setError(
        "Changes could not be saved. Your edits are still here. Try again.",
      );
    } finally {
      setPending(false);
      if (!user) {
        setPassword("");
        setConfirmation("");
      }
    }
  }
  return (
    <main className="access-page access-editor">
      {!storyNavigation && <a
        className="access-back"
        href="/users"
        onClick={(event) => {
          event.preventDefault();
          onNavigate("/users");
        }}
      >
        <ArrowLeft size={16} aria-hidden />
        Back to users
      </a>}
      <PageHeader
        title={user ? "User details" : "Create user"}
        description={
          user ? user.email : "Set up an account and choose where it can work."
        }
      />
      {!role ? (
        <FormMessage error>This account's role is unavailable. Reload and try again.</FormMessage>
      ) : null}
      {!editable && role ? (
        <FormMessage>This account is read-only for your role.</FormMessage>
      ) : null}
      {role ? (
      <form onSubmit={submit} className="access-form">
        <fieldset disabled={pending} className="access-fieldset">
          <section className="access-section access-identity">
            <FormField
              label="Email"
              type="email"
              autoComplete="off"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              readOnly={!editable}
              hint="Used to sign in. No email will be sent."
            />
            {!user ? (
              <PasswordFields
                password={password}
                confirmation={confirmation}
                onPassword={setPassword}
                onConfirmation={setConfirmation}
              />
            ) : null}
            <RoleSelect
              actor={actorRole}
              roles={roles}
              value={roleId}
              onChange={(value) => {
                setRoleId(value);
                if (!loadRole) setMemberships([]);
                setNotice("Role changed. Review tenant access before saving.");
              }}
              readOnly={!editable}
            />
            {user ? (
              <div className="access-field">
                <label htmlFor="user-status">Account status</label>
                {editable ? (
                  <select
                    id="user-status"
                    value={enabled ? "active" : "disabled"}
                    onChange={(event) =>
                      setEnabled(event.target.value === "active")
                    }
                  >
                    <option value="active">Active</option>
                    <option value="disabled">Disabled</option>
                  </select>
                ) : (
                  <p>{enabled ? "Active" : "Disabled"}</p>
                )}
              </div>
            ) : null}
          </section>
          <TenantAccessEditor
            role={role}
            tenants={tenants}
            value={memberships}
            onChange={setMemberships}
            readOnly={!editable || !roleReady || limitedRole}
          />
          {loadRole && !roleReady ? (
            currentRead?.phase === "unavailable" ? (
              <FormMessage error>
                The selected role could not be loaded. Retry before saving.
                <Button type="button" onClick={() => {
                  setRoleRead({ id: roleId, phase: "loading", role: null });
                  setRoleRetry(value => value + 1);
                }}>Retry role details</Button>
              </FormMessage>
            ) : <p role="status">Loading role details…</p>
          ) : null}
          {notice ? <FormMessage>{notice}</FormMessage> : null}
          {error ? <FormMessage error>{error}</FormMessage> : null}
          {editable ? (
            <div className="access-actions">
              <Button
                type="submit"
                className="access-primary"
                disabled={pending || !roleReady}
              >
                {pending ? "Saving…" : user ? "Save changes" : "Create user"}
              </Button>
              <Button
                type="button"
                variant="ghost"
                onClick={() => onNavigate("/users")}
              >
                Cancel
              </Button>
            </div>
          ) : null}
        </fieldset>
      </form>
      ) : null}
      {user && editable ? (
        <section className="access-section access-security">
          <div>
            <h2>Password</h2>
            <p className="access-muted">
              Set a replacement password and sign out existing sessions.
            </p>
          </div>
          <a
            className="access-link-button"
            href={`/users/${user.id}/reset-password`}
            onClick={(event) => {
              event.preventDefault();
              onNavigate(`/users/${user.id}/reset-password`);
            }}
          >
            <KeyRound size={16} aria-hidden />
            Reset password
          </a>
        </section>
      ) : null}
    </main>
  );
}
