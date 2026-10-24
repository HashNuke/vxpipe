import { useEffect, useState, type ReactNode } from "react";
import { AccessFrame } from "./AccessFrame";
import { AccountPage } from "./AccountPage";
import { AuthPage } from "./AuthPage";
import { InstallationSettingsPage } from "./InstallationSettingsPage";
import { FormMessage } from "./FormField";
import { ResetPasswordPage } from "./ResetPasswordPage";
import { RoleEditorPage } from "./RoleEditorPage";
import { RolesPage } from "./RolesPage";
import { UserEditorPage } from "./UserEditorPage";
import { UsersPage } from "./UsersPage";
import { canManageUser, canReadUsers, hasAssignedGrants } from "./access";
import { roles as seedRoles, tenants, users as seedUsers } from "./fixtures";
import type { PageState, Role, Theme, User } from "./types";

export type Actor = "superadmin" | "admin" | "member";
const actorIndex = { superadmin: 0, admin: 1, member: 4 };
export function AuthenticationJourney({
  actor = "superadmin",
  initialPath = "/users",
  theme = "dark",
  state = "ready",
  saveBehavior = "success",
  followLocation = true,
  initialPublicUrl = "https://calls.example.test",
  renderFrame,
}: {
  actor?: Actor;
  initialPath?: string;
  theme?: Theme;
  state?: PageState;
  saveBehavior?: "success" | "failure" | "pending";
  followLocation?: boolean;
  initialPublicUrl?: string;
  renderFrame?: (children: ReactNode, path: string, session: { user?: User; role?: Role; navigate: (path: string) => void; logout: () => void }) => ReactNode;
}) {
  const [roles, setRoles] = useState<Role[]>(structuredClone(seedRoles));
  const [users, setUsers] = useState<User[]>(
    initialPath === "/auth/setup" ? [] : structuredClone(seedUsers),
  );
  const [actorId, setActorId] = useState<string | null>(
    initialPath.startsWith("/auth/") ? null : seedUsers[actorIndex[actor]].id,
  );
  const [location, setLocation] = useState(() =>
    followLocation && /^#\/(users|roles|account)(\/|$)/.test(window.location.hash)
      ? window.location.hash.slice(1)
      : initialPath,
  );
  const [notice, setNotice] = useState<string>();
  const [publicUrl, setPublicUrl] = useState(initialPublicUrl);
  const [installationState, setInstallationState] = useState(state);
  useEffect(() => {
    const update = () => {
      if (window.location.hash.startsWith("#/"))
        setLocation(window.location.hash.slice(1));
    };
    window.addEventListener("popstate", update);
    window.addEventListener("hashchange", update);
    return () => {
      window.removeEventListener("popstate", update);
      window.removeEventListener("hashchange", update);
    };
  }, []);
  function navigate(path: string) {
    window.history.pushState({}, "", `#${path}`);
    setLocation(path);
    setNotice(undefined);
  }
  async function result() {
    if (saveBehavior === "pending")
      return new Promise<string | undefined>(() => undefined);
    await Promise.resolve();
    return saveBehavior === "failure"
      ? "Changes could not be saved. Try again. Your previous settings are unchanged."
      : undefined;
  }
  const route = new URL(location, "http://storybook.invalid");
  const path = route.pathname;
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: "instant" });
  }, [path]);
  const currentUser = users.find((user) => user.id === actorId);
  const currentRole = roles.find((role) => role.id === currentUser?.roleId);
  const denied = (
    <main className="access-page">
      <h1>Access unavailable</h1>
      <p className="access-lead">Your role does not allow this action.</p>
    </main>
  );
  let page;
  if (
    path === "/auth/setup" ||
    path === "/auth/login" ||
    path === "/auth/recover" ||
    !currentUser ||
    !currentRole
  ) {
    const setup = path === "/auth/setup";
    const recover = path === "/auth/recover";
    page = (
      <AuthPage
        key={setup ? "setup" : recover ? "recover" : "login"}
        mode={setup ? "setup" : recover ? "recover" : "login"}
        configureUrl
        completed={setup && users.length > 0}
        unavailable={state === "unavailable"}
        onSubmit={async (email, password, _proof, url) => {
          const error = await result();
          if (error) return { error };
          if (!password) return { error: "Enter your password." };
          if (setup) {
            const owner: User = {
              id: crypto.randomUUID(),
              email,
              roleId: roles[0].id,
              enabled: true,
              memberships: [],
            };
            setUsers([owner]);
            setActorId(owner.id);
            setPublicUrl(url ?? "");
          } else {
            const user = users.find(
              (item) =>
                item.email.toLowerCase() === email.toLowerCase() &&
                (recover ? roles.find((role) => role.id === item.roleId)?.kind === "superadmin" : item.enabled),
            );
            if (!user) return { error: "Email or password is incorrect." };
            setActorId(user.id);
          }
          navigate(setup ? "/platform/installation" : "/account");
          return {};
        }}
      />
    );
  } else if (path === "/platform/installation") {
    page = <InstallationSettingsPage roleKind={currentRole.kind} publicUrl={publicUrl} state={installationState}
      onRetry={() => setInstallationState("ready")} onSave={async url => {
        const error = await result();
        if (error) return { error };
        setPublicUrl(url);
        return {};
      }} />;
  } else if (path === "/account") {
    page = (
      <AccountPage
        key={currentUser.id}
        user={currentUser}
        role={currentRole}
        onSave={async (email) => {
          const error = await result();
          if (error) return { error };
          if (
            users.some(
              (user) =>
                user.id !== currentUser.id &&
                user.email.toLowerCase() === email.toLowerCase(),
            )
          )
            return { error: "That email is already used by another account." };
          setUsers(
            users.map((user) =>
              user.id === currentUser.id ? { ...user, email } : user,
            ),
          );
          setActorId(null);
          navigate("/auth/login");
          setNotice("Account updated. Sign in again with your new details.");
          return {};
        }}
      />
    );
  } else if (path === "/users") {
    page = canReadUsers(currentRole) ? (
      <UsersPage
        users={users}
        roles={roles}
        actorRole={currentRole}
        query={route.searchParams}
        onQuery={(query) =>
          navigate(`/users${query.size ? `?${query}` : ""}`)
        }
        onNavigate={navigate}
        state={state}
      />
    ) : (
      denied
    );
  } else if (path.startsWith("/users/")) {
    const targetId = path.split("/")[2];
    const creating = targetId === "new";
    const target = users.find((user) => user.id === targetId);
    const targetRole = roles.find((role) => role.id === target?.roleId);
    if (
      (!creating && (!target || !targetRole)) ||
      !canReadUsers(currentRole) ||
      (creating && !currentRole.kind)
    )
      page = denied;
    else if (path.endsWith("/reset-password") && target && targetRole) {
      page = (
        <ResetPasswordPage
          key={target.id}
          actorRole={currentRole}
          targetRole={targetRole}
          user={target}
          onNavigate={navigate}
          onReset={async () => {
            if (!canManageUser(currentRole, targetRole))
              return { error: "Your role cannot reset this account." };
            const error = await result();
            if (error) return { error };
            if (target.id === currentUser.id) {
              setActorId(null);
              navigate("/auth/login");
            } else navigate(`/users/${target.id}`);
            setNotice("Password updated. Existing sessions were signed out.");
            return {};
          }}
        />
      );
    } else
      page = (
        <UserEditorPage
          key={creating ? "new" : target!.id}
          actorRole={currentRole}
          roles={roles}
          tenants={tenants}
          user={target}
          onNavigate={navigate}
          onSave={async (draft) => {
            const nextRole = roles.find((role) => role.id === draft.roleId)!;
            if (!canManageUser(currentRole, targetRole ?? nextRole, nextRole))
              return { error: "Your role cannot make this account change." };
            if (
              users.some(
                (user) =>
                  user.id !== target?.id &&
                  user.email.toLowerCase() === draft.email.toLowerCase(),
              )
            )
              return {
                error: "That email is already used by another account.",
              };
            if (
              targetRole?.kind === "superadmin" &&
              (!draft.enabled || nextRole.kind !== "superadmin") &&
              users.filter(
                (user) =>
                  user.enabled &&
                  roles.find((role) => role.id === user.roleId)?.kind ===
                    "superadmin",
              ).length === 1
            )
              return {
                error:
                  "Keep at least one active Superadmin. Add another before changing this account.",
              };
            const error = await result();
            if (error) return { error };
            const updated = { ...draft, id: target?.id ?? crypto.randomUUID() };
            setUsers(
              creating
                ? [...users, updated]
                : users.map((user) =>
                    user.id === updated.id ? updated : user,
                  ),
            );
            if (target?.id === currentUser.id) {
              setActorId(null);
              navigate("/auth/login");
            } else if (creating) {
              navigate(`/users/${updated.id}`);
              setNotice(
                "User created. Share their chosen password outside the Console.",
              );
            }
            return {};
          }}
        />
      );
  } else if (path === "/roles")
    page = currentRole.kind ? (
      <RolesPage
        roles={roles}
        affectedUsers={Object.fromEntries(
          roles.map((role) => [
            role.id,
            users.filter((user) => user.roleId === role.id).length,
          ]),
        )}
        onNavigate={navigate}
      />
    ) : (
      denied
    );
  else if (path.startsWith("/roles/")) {
    const id = path.split("/")[2];
    const role = roles.find((item) => item.id === id);
    page =
      !currentRole.kind || (id !== "new" && !role) ? (
        denied
      ) : (
        <RoleEditorPage
          key={id}
          role={role}
          affectedUsers={users.filter((user) => user.roleId === id).length}
          onNavigate={navigate}
          onSave={async (draft) => {
            if (role?.kind)
              return { error: "Built-in roles cannot be changed." };
            if (
              roles.some(
                (item) =>
                  item.id !== id &&
                  item.name.toLowerCase() === draft.name.toLowerCase(),
              )
            )
              return { error: "Choose a unique role name." };
            if (
              draft.grants.some((grant) =>
                /^users\..+\.write$/.test(grant.permission),
              )
            )
              return {
                error: "Account writes cannot be granted to a custom role.",
              };
            const error = await result();
            if (error) return { error };
            const updated: Role = {
              ...draft,
              id: role?.id ?? crypto.randomUUID(),
              kind: null,
            };
            setRoles(
              role
                ? roles.map((item) => (item.id === id ? updated : item))
                : [...roles, updated],
            );
            if (!hasAssignedGrants(updated))
              setUsers(
                users.map((user) =>
                  user.roleId === updated.id
                    ? { ...user, memberships: [] }
                    : user,
                ),
              );
            if (!role) {
              navigate(`/roles/${updated.id}`);
              setNotice("Role created. It is ready to assign to users.");
            }
            return {};
          }}
          onDelete={async () => {
            if (role?.kind || users.some((user) => user.roleId === id))
              return { error: "Reassign users before deleting this role." };
            const error = await result();
            if (error) return { error };
            setRoles(roles.filter((item) => item.id !== id));
            navigate("/roles");
            setNotice("Role deleted.");
            return {};
          }}
        />
      );
  } else page = denied;
  if (renderFrame) return renderFrame(<div className="access-ui">{notice ? <div className="access-notice"><FormMessage>{notice}</FormMessage></div> : null}{page}</div>, path, { user: currentUser, role: currentRole, navigate, logout: () => { setActorId(null); navigate("/auth/login"); } });
  return (
    <AccessFrame
      theme={theme}
      actor={currentUser}
      role={currentRole}
      path={path}
      onNavigate={navigate}
      onLogout={() => {
        setActorId(null);
        navigate("/auth/login");
      }}
    >
      {notice ? (
        <div className="access-notice">
          <FormMessage>{notice}</FormMessage>
        </div>
      ) : null}
      {page}
    </AccessFrame>
  );
}
