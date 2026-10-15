import { ApiKeysRoute } from "./admin/apiKeys/ApiKeysRoute";
import { callSpecSearch } from "./admin/callSpecSearch";
import { TenantCreationPage } from "./admin/navigation/TenantCreationPage";
import { NavigationError } from "./admin/navigation/navigationApi";
import { NavigationContext } from "./admin/navigation/navigationContext";
import { ConsoleNavigation } from "./admin/navigation/ConsoleNavigation";
import { WorkspaceDashboard, WorkspaceDirectory } from "./admin/navigation/WorkspacePages";
import {
  createContext,
  useContext,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
  type Dispatch,
  type MutableRefObject,
  type SetStateAction,
} from "react";
import {
  createBrowserRouter,
  createRoutesFromElements,
  RouterProvider,
  Navigate,
  Route,
  useLocation,
  useNavigate,
  useParams,
  useSearchParams,
} from "react-router";
import {
  createCallDetailsController,
  createCallDetailsStore,
  type CallDetailsController,
  type CallDetailsLoader,
} from "@vxpipe/core";

import {
  parseCallPage,
  parseCreatedCredential,
  parseCallSpecPage,
  parseDemoTenant,
  parseInstalledSamples,
  parseServiceDirectory,
  parseTenantPage,
} from "./admin/adminApi";
import { shouldInterceptNavigation } from "./admin/shouldInterceptNavigation";
import { CallSpecCallsPage } from "./admin/CallSpecCallsPage";
import { OnboardingPage } from "./admin/OnboardingPage";
import {
  onboardingProvider,
  onboardingSamples,
} from "./admin/onboardingFixtures";
import type { OnboardingPageState } from "./admin/onboardingTypes";
import { CallDetailsPage } from "./admin/CallDetailsPage";
import {
  parseAdminCallDetails,
  type AdminCallDetails,
} from "./admin/adminCallDetailsApi";
import type { CallDetailsPageState } from "./admin/callDetailsTypes";
import type { CallSpecCallsPageState } from "./admin/callTypes";
import { TenantCallSpecsPage } from "./admin/TenantCallSpecsPage";
import type { TenantCallSpecsPageState } from "./admin/callSpecTypes";
import type {
  CredentialDraft,
  ServiceInventoryItem,
  TenantServicesPageState,
} from "./admin/serviceTypes";
import {
  credentialRequest,
  testCredentialRequest,
} from "./admin/credentialApi";
import { TenantServicesPage } from "./admin/TenantServicesPage";
import { TenantsPage } from "./admin/TenantsPage";
import { CallSpecEditorRoute } from "./CallSpecEditorRoute";
import { ScopedServicesApp } from "./ScopedServicesApp";
import { parseBindingDirectory } from "./admin/serviceBindingsApi";
import { AccessFrame } from "./admin/authentication/AccessFrame";
import { AccountPage } from "./admin/authentication/AccountPage";
import { AuthPage } from "./admin/authentication/AuthPage";
import { AuthenticationApi, AuthenticationError, isForbidden, isSessionExpired } from "./admin/authentication/authenticationApi";
import { ResetPasswordPage } from "./admin/authentication/ResetPasswordPage";
import { RoleEditorPage } from "./admin/authentication/RoleEditorPage";
import { RolesPage } from "./admin/authentication/RolesPage";
import { UserEditorPage } from "./admin/authentication/UserEditorPage";
import { UsersPage } from "./admin/authentication/UsersPage";
import type { Role as AccessRole, Tenant as AccessTenant, User as AccessUser } from "./admin/authentication/types";
import {
  canCreateCallSpecs,
  canCreateTenants,
  canReadPlatformServices,
  canWritePlatformServices,
  canReadUsers,
  canWriteTenantCredentials,
  membershipAccess,
  workspaceDestinationsFor,
} from "./admin/authentication/access";
import { FormMessage } from "./admin/authentication/FormField";
import { PageNotice } from "./admin/PageNotice";
import type { PaginationModel, TenantsPageState } from "./admin/tenantTypes";

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type AdminRoute =
  | { kind: "onboarding" }
  | { kind: "tenants"; page: number }
  | { kind: "call-specs"; tenantKey: string; page: number }
  | { kind: "calls"; tenantKey: string; callSpecId: string | null; page: number }
  | { kind: "call-details"; tenantKey: string; callId: string }
  | { kind: "services"; tenantKey: string };

type AppProps = {
  csrfToken: string;
  fetchImpl?: Fetch;
  onSessionExpired?: () => void;
  onAuthenticated?: () => void;
};

const defaultFetch: Fetch = (input, init) => window.fetch(input, init);
const redirectExpiredSession = () => window.location.assign("/auth/login");

const AppConfiguration = createContext<AppProps>({ csrfToken: "" });

function ConfiguredRoute({ render }: { render: (props: AppProps) => ReactNode }) {
  const props = useContext(AppConfiguration);
  const navigation = useContext(NavigationContext);
  const fail = navigation?.fail;
  const refresh = navigation?.refresh;
  const fetchImpl = useMemo(() => {
    if (!fail || !refresh) return props.fetchImpl;
    const fetch = props.fetchImpl ?? defaultFetch;
    return async (input: RequestInfo | URL, init?: RequestInit) => {
      const response = await fetch(input, init);
      if (!init?.signal?.aborted) {
        if (response.status === 401) fail(new NavigationError(401));
        else if (response.status === 403) refresh();
      }
      return response;
    };
  }, [props.fetchImpl, fail, refresh]);
  const onSessionExpired = useCallback(() => fail?.(new NavigationError(401)), [fail]);
  return render({ ...props, fetchImpl, onSessionExpired: fail ? onSessionExpired : props.onSessionExpired });
}

export function App(props: AppProps) {
  const [router] = useState(() => createBrowserRouter(createRoutesFromElements(
      <>
        <Route path="/auth/setup" element={<ConfiguredRoute render={(props) => <AuthenticationRoute {...props} mode="setup" />} />} />
        <Route path="/auth/login" element={<ConfiguredRoute render={(props) => <AuthenticationRoute {...props} mode="login" />} />} />
        <Route path="/auth/recover" element={<ConfiguredRoute render={(props) => <AuthenticationRoute {...props} mode="recover" />} />} />
        <Route element={<ConfiguredRoute render={props => <ConsoleNavigation {...props} />} />}>
        <Route path="/account" element={<ConfiguredRoute render={(props) => <AccountRoute {...props} />} />} />
        <Route path="/users/new" element={<ConfiguredRoute render={(props) => <UserNewRoute {...props} />} />} />
        <Route path="/users/:id/reset-password" element={<ConfiguredRoute render={(props) => <ResetPasswordRoute {...props} />} />} />
        <Route path="/users/:id" element={<ConfiguredRoute render={(props) => <UserDetailRoute {...props} />} />} />
        <Route path="/users" element={<ConfiguredRoute render={(props) => <UsersRoute {...props} />} />} />
        <Route path="/roles/new" element={<ConfiguredRoute render={(props) => <RoleNewRoute {...props} />} />} />
        <Route path="/roles/:id" element={<ConfiguredRoute render={(props) => <RoleDetailRoute {...props} />} />} />
        <Route path="/roles" element={<ConfiguredRoute render={(props) => <RolesRoute {...props} />} />} />
        <Route path="/api-keys" element={<ConfiguredRoute render={props => <ApiKeysRoute {...props} />} />} />
        <Route path="/api-keys/new" element={<ConfiguredRoute render={props => <ApiKeysRoute {...props} />} />} />
        <Route path="/platform/services" element={<ConfiguredRoute render={(props) => <ScopedServicesRoute {...props} platform />} />} />
        <Route path="/" element={<WorkspaceDirectory />} />
        <Route path="/tenants" element={<WorkspaceDirectory />} />
        <Route path="/tenants/new" element={<TenantCreationPage />} />
        <Route path="/my-tenants" element={<WorkspaceDirectory />} />
        <Route path="/t/:tenantKey/dashboard" element={<WorkspaceDashboard />} />
        <Route path="/t/:tenantKey/call-specs" element={<ConfiguredRoute render={props => <CallSpecsRoute {...props} />} />} />
        <Route path="/t/:tenantKey/calls" element={<ConfiguredRoute render={props => <CallsRoute {...props} />} />} />
        <Route path="/t/:tenantKey/services" element={<ConfiguredRoute render={props => <ServicesRoute {...props} />} />} />
        <Route path="/getting-started" element={<ConfiguredRoute render={props => <RoutedApp {...props} route={{ kind: "onboarding" }} />} />} />
        </Route>
        <Route path="/admin/tenants/:tenantKey/call-specs/:callSpecId" element={<ConfiguredRoute render={(props) => <CallSpecEditorRoute {...props} />} />} />
        <Route path="/admin/tenants/:tenantKey/calls/:callId" element={<ConfiguredRoute render={(props) => <CallDetailsRoute {...props} />} />} />
        <Route path="/admin/*" element={<LegacyPageRedirect />} />
        <Route path="*" element={<Navigate replace to="/" />} />
      </>
  )));
  useEffect(() => () => router.dispose(), [router]);
  return <AppConfiguration value={props}><RouterProvider router={router} /></AppConfiguration>;
}

function AuthenticationRoute(props: AppProps & { mode: "setup" | "login" | "recover" }) {
  const navigate = useNavigate();
  const location = useLocation();
  const notice =
    typeof location.state === "object" && location.state !== null && "notice" in location.state
      ? String((location.state as { notice: unknown }).notice)
      : undefined;
  const api = useAuthenticationApi(props);
  const [status, setStatus] = useState<"loading" | "ready" | "unavailable">("loading");
  const [completed, setCompleted] = useState(false);
  const [proofRequired, setProofRequired] = useState(false);

  useEffect(() => {
    let active = true;
    api.status().then(({ status: setupStatus }) => {
      if (!active) return;
      setCompleted(setupStatus === "complete");
      setProofRequired(setupStatus === "pending_operator_proof");
      if (setupStatus !== "complete" && props.mode !== "setup")
        navigate("/auth/setup", { replace: true });
      else if (setupStatus === "complete" && props.mode === "setup")
        navigate("/auth/login", { replace: true });
      setStatus("ready");
    }).catch(() => {
      if (active) setStatus("unavailable");
    });
    return () => { active = false; };
  }, [api, navigate, props.mode]);

  return (
    <AccessFrame>
      {status === "loading" ? <main className="access-auth" role="status">Loading…</main> :
        <>
          {notice ? (
            <div className="access-notice">
              <FormMessage>{notice}</FormMessage>
            </div>
          ) : null}
          <AuthPage
          mode={props.mode}
          completed={completed && props.mode === "setup"}
          proofRequired={proofRequired}
          unavailable={status === "unavailable"}
          onSubmit={async (email, password, proof) => {
            try {
              if (props.mode === "setup") await api.setup(email, password, password, proof);
              else if (props.mode === "recover") await api.recover(proof ?? "", email, password, password);
              else await api.login(email, password);
              // Session renewal replaces CSRF state; load a fresh document before writes.
              (props.onAuthenticated ?? (() => window.location.assign("/")))();
              return {};
            } catch (error) {
              return { error: error instanceof Error ? error.message : "Unable to sign in." };
            }
          }}
          />
        </>}
    </AccessFrame>
  );
}

function UsersRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const [query, setQuery] = useSearchParams();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const { roles, rolesLimited, rolesState } = useAccessRoles(api, sessionState === "ready", onSessionExpired);
  const [users, setUsers] = useState<AccessUser[]>([]);
  const [pagination, setPagination] = useState<{ page: number; page_size: number; total: number; total_pages: number }>();
  const [directoryState, setDirectoryState] = useState<AccessLoadState>("loading");

  useEffect(() => {
    if (sessionState !== "ready" || rolesState !== "ready") return;
    let active = true;
    api.users(query).then((page) => {
      if (!active) return;
      setUsers(page.users);
      setPagination(page.pagination);
      setDirectoryState("ready");
    }).catch((error: unknown) => {
      if (!active) return;
      if (isSessionExpired(error)) {
        onSessionExpired();
        return;
      }
      if (error instanceof AuthenticationError && error.status === 422) {
        const page = Number(query.get("page"));
        if (query.get("page") !== null && Number.isInteger(page) && page > 1) {
          const next = new URLSearchParams(query);
          next.delete("page");
          setQuery(next, { replace: true });
          return;
        }
        // Invalid filters (for example an unknown role) keep their URL and
        // render the directory empty so the page can explain the filter.
        setUsers([]);
        setPagination(undefined);
        setDirectoryState("ready");
        return;
      }
      setDirectoryState("unavailable");
    });
    return () => { active = false; };
  }, [api, query, sessionState, rolesState, onSessionExpired, setQuery]);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/users"
      statusLabel="Loading users…"
      unavailableTitle="Users unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {({ role }) => {
        if (rolesState === "unavailable" || directoryState === "unavailable") {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Users unavailable"
                message="The directory could not be loaded. Try again shortly."
              />
            </main>
          );
        }
        // The directory heading renders together with its rows so links,
        // filters and pagination share one consistent server result.
        if (rolesState !== "ready" || directoryState !== "ready") {
          return <main className="access-page" role="status">Loading users…</main>;
        }
        return (
          <UsersPage
            users={users}
            roles={roles}
            rolesLimited={rolesLimited}
            actorRole={role}
            query={query}
            onQuery={setQuery}
            onNavigate={navigate}
            state="ready"
            pagination={pagination}
          />
        );
      }}
    </AccessShell>
  );
}

function AccountRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/account"
      statusLabel="Loading account…"
      unavailableTitle="Account unavailable"
      unavailableMessage="Your account could not be loaded. Try again shortly."
    >
      {({ user, role }) => (
        <AccountPage
          key={user.id}
          user={user}
          role={role}
          onSave={async (email, currentPassword, newPassword, confirmation) => {
            try {
              await api.updateAccount(email, currentPassword, newPassword, confirmation);
              if (newPassword) {
                // Changing the password revokes every session, including
                // this one. Explain the sign-out and redirect to sign-in
                // instead of leaving a dead session on the account page.
                navigate("/auth/login", {
                  state: {
                    notice:
                      "Password changed. Your sessions were signed out. Sign in again with your new password.",
                  },
                });
              }
              return {};
            } catch (error: unknown) {
              if (isSessionExpired(error)) onSessionExpired();
              return { error: accessError(error) };
            }
          }}
        />
      )}
    </AccessShell>
  );
}

function UserNewRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const loadRole = useRoleReader(api, onSessionExpired);
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const { roles, rolesState } = useAccessRoles(api, sessionState === "ready", onSessionExpired);
  const tenants = useTenantOptions(api, sessionState === "ready", onSessionExpired);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/users"
      statusLabel="Loading…"
      unavailableTitle="Users unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {(current) => {
        if (!current.role.kind) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Access unavailable"
                message="Your role does not allow this action."
              />
            </main>
          );
        }
        if (rolesState !== "ready") {
          return rolesState === "unavailable" ? (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Users unavailable"
                message="The directory could not be loaded. Try again shortly."
              />
            </main>
          ) : (
            <main className="access-page" role="status">Loading…</main>
          );
        }
        return (
          <UserEditorPage
            actorRole={current.role}
            roles={roles}
            loadRole={loadRole}
            tenants={tenants}
            onNavigate={navigate}
            onSave={async (draft, password) => {
              try {
                const { user } = await api.createUser({
                  email: draft.email,
                  password: password ?? "",
                  passwordConfirmation: password ?? "",
                  roleId: draft.roleId,
                  memberships: draft.memberships,
                });
                navigate(`/users/${user.id}`);
                return {};
              } catch (error: unknown) {
                if (isSessionExpired(error)) onSessionExpired();
                return { error: accessError(error) };
              }
            }}
          />
        );
      }}
    </AccessShell>
  );
}

function UserDetailRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const loadRole = useRoleReader(api, onSessionExpired);
  const { id = "" } = useParams();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const { roles, rolesState } = useAccessRoles(api, sessionState === "ready", onSessionExpired);
  const tenants = useTenantOptions(api, sessionState === "ready", onSessionExpired);
  const [target, setTarget] = useState<AccessUser | null>(null);
  const [detail, setDetail] = useState<AccessLoadState | "missing" | "denied">("loading");

  useEffect(() => {
    if (sessionState !== "ready") return;
    let active = true;
    setDetail("loading");
    api.user(id).then(({ user }) => {
      if (!active) return;
      setTarget(user);
      setDetail("ready");
    }).catch((error: unknown) => {
      if (!active) return;
      if (isSessionExpired(error)) {
        onSessionExpired();
        return;
      }
      if (error instanceof AuthenticationError && error.status === 404) setDetail("missing");
      else if (isForbidden(error)) setDetail("denied");
      else setDetail("unavailable");
    });
    return () => { active = false; };
  }, [api, id, sessionState, onSessionExpired]);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/users"
      statusLabel="Loading user…"
      unavailableTitle="Users unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {(current) => {
        if (detail === "loading" || rolesState === "loading") {
          return <main className="access-page" role="status">Loading user…</main>;
        }
        if (detail === "missing") {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="User not found"
                message="This account could not be found."
              />
            </main>
          );
        }
        if (detail === "denied") {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Access unavailable"
                message="Your role does not allow this action."
              />
            </main>
          );
        }
        if (detail === "unavailable" || rolesState === "unavailable" || !target) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="User unavailable"
                message="This account could not be loaded. Try again shortly."
              />
            </main>
          );
        }
        return (
          <UserEditorPage
            key={target.id}
            actorRole={current.role}
            roles={roles}
            loadRole={loadRole}
            tenants={tenants}
            user={target}
            onNavigate={navigate}
            onSave={async (draft) => {
              try {
                const { user: updated } = await api.updateUser(target.id, {
                  email: draft.email,
                  roleId: draft.roleId,
                  enabled: draft.enabled,
                  memberships: draft.memberships,
                });
                setTarget(updated);
                return {};
              } catch (error: unknown) {
                if (isSessionExpired(error)) onSessionExpired();
                return { error: accessError(error) };
              }
            }}
          />
        );
      }}
    </AccessShell>
  );
}

function ResetPasswordRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const { id = "" } = useParams();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const { roles, rolesState } = useAccessRoles(api, sessionState === "ready", onSessionExpired);
  const [target, setTarget] = useState<AccessUser | null>(null);
  const [detail, setDetail] = useState<AccessLoadState | "missing" | "denied">("loading");

  useEffect(() => {
    if (sessionState !== "ready") return;
    let active = true;
    setDetail("loading");
    api.user(id).then(({ user }) => {
      if (!active) return;
      setTarget(user);
      setDetail("ready");
    }).catch((error: unknown) => {
      if (!active) return;
      if (isSessionExpired(error)) {
        onSessionExpired();
        return;
      }
      if (error instanceof AuthenticationError && error.status === 404) setDetail("missing");
      else if (isForbidden(error)) setDetail("denied");
      else setDetail("unavailable");
    });
    return () => { active = false; };
  }, [api, id, sessionState, onSessionExpired]);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/users"
      statusLabel="Loading user…"
      unavailableTitle="Users unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {(current) => {
        if (detail === "loading" || rolesState === "loading") {
          return <main className="access-page" role="status">Loading user…</main>;
        }
        const targetRole = roles.find((role) => role.id === target?.roleId);
        if (detail !== "ready" || !target || !targetRole) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title={detail === "denied" ? "Access unavailable" : "User unavailable"}
                message={
                  detail === "denied"
                    ? "Your role does not allow this action."
                    : "This account could not be loaded. Try again shortly."
                }
              />
            </main>
          );
        }
        return (
          <ResetPasswordPage
            key={target.id}
            actorRole={current.role}
            targetRole={targetRole}
            user={target}
            onNavigate={navigate}
            onReset={async (password) => {
              try {
                // The page only calls back after its confirmation matches,
                // so the confirmed value doubles as the server confirmation.
                await api.resetPassword(target.id, password, password);
                return {};
              } catch (error: unknown) {
                if (isSessionExpired(error)) onSessionExpired();
                return { error: accessError(error) };
              }
            }}
          />
        );
      }}
    </AccessShell>
  );
}

function RolesRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const [query, setQuery] = useSearchParams();
  const page = readPage(query);
  const [pagination, setPagination] = useState<{page:number;page_size:number;total:number;total_pages:number}>();
  const [roles, setRoles] = useState<AccessRole[]>([]);
  const [affectedUsers, setAffectedUsers] = useState<Record<string, number>>({});
  const [directoryState, setDirectoryState] = useState<AccessLoadState | "denied">("loading");

  useEffect(() => {
    if (sessionState !== "ready") return;
    let active = true;
    setDirectoryState("loading");
    (async () => {
      const { roles: directory, pagination: nextPagination } = await api.roles(page);
      if (!active) return;
      setRoles(directory);
      setPagination(nextPagination);
      setAffectedUsers({});
      // Counts come from the authoritative per-role endpoint; a bounded
      // user-directory scan would present partial counts as authoritative.
      const counts: Record<string, number> = {};
      for (const entry of directory) {
        if (!active) return;
        const detail = await api.role(entry.id).catch((error: unknown) => {
          if (isSessionExpired(error) || isForbidden(error)) throw error;
          return null;
        });
        if (detail) counts[entry.id] = detail.affected_users;
      }
      if (active) setAffectedUsers(counts);
    })().then(
      () => { if (active) setDirectoryState("ready"); },
      (error: unknown) => {
        if (!active) return;
        if (isSessionExpired(error)) {
          onSessionExpired();
          return;
        }
        if (error instanceof AuthenticationError && error.status === 422 && error.code === "page_out_of_range" && page !== 1) {
          setQuery({}, {replace:true});
          return;
        }
        setDirectoryState(isForbidden(error) ? "denied" : "unavailable");
      },
    );
    return () => { active = false; };
  }, [api, sessionState, onSessionExpired, page, setQuery]);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/roles"
      statusLabel="Loading roles…"
      unavailableTitle="Roles unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {(current) => {
        if (directoryState === "loading") {
          return <main className="access-page" role="status">Loading roles…</main>;
        }
        if (directoryState === "denied" || !current.role.kind) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Access unavailable"
                message="Your role does not allow this action."
              />
            </main>
          );
        }
        if (directoryState === "unavailable") {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Roles unavailable"
                message="Roles could not be loaded. Try again shortly."
              />
            </main>
          );
        }
        return <RolesPage roles={roles} affectedUsers={affectedUsers} onNavigate={navigate} pagination={pagination} onPage={(next) => setQuery(next === 1 ? {} : {page:String(next)})} />;
      }}
    </AccessShell>
  );
}

function RoleNewRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/roles"
      statusLabel="Loading…"
      unavailableTitle="Roles unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {(current) => {
        if (!current.role.kind) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Access unavailable"
                message="Your role does not allow this action."
              />
            </main>
          );
        }
        return (
          <RoleEditorPage
            onNavigate={navigate}
            onSave={async (draft) => {
              try {
                const { role } = await api.createRole(draft);
                navigate(`/roles/${role.id}`);
                return {};
              } catch (error: unknown) {
                if (isSessionExpired(error)) onSessionExpired();
                return { error: accessError(error) };
              }
            }}
          />
        );
      }}
    </AccessShell>
  );
}

function RoleDetailRoute(props: AppProps) {
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const navigate = useNavigate();
  const { id = "" } = useParams();
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const [entry, setEntry] = useState<{ role: AccessRole; affectedUsers: number } | null>(null);
  const [detail, setDetail] = useState<AccessLoadState | "missing" | "denied">("loading");

  useEffect(() => {
    if (sessionState !== "ready") return;
    let active = true;
    setDetail("loading");
    api.role(id).then(({ role, affected_users }) => {
      if (!active) return;
      setEntry({ role, affectedUsers: affected_users });
      setDetail("ready");
    }).catch((error: unknown) => {
      if (!active) return;
      if (isSessionExpired(error)) {
        onSessionExpired();
        return;
      }
      if (error instanceof AuthenticationError && error.status === 404) setDetail("missing");
      else if (isForbidden(error)) setDetail("denied");
      else setDetail("unavailable");
    });
    return () => { active = false; };
  }, [api, id, sessionState, onSessionExpired]);

  return (
    <AccessShell
      api={api}
      session={session}
      sessionState={sessionState}
      path="/roles"
      statusLabel="Loading role…"
      unavailableTitle="Roles unavailable"
      unavailableMessage="Your session could not be loaded. Try again shortly."
    >
      {(current) => {
        if (detail === "loading") {
          return <main className="access-page" role="status">Loading role…</main>;
        }
        if (detail === "missing") {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Role not found"
                message="This role could not be found."
              />
            </main>
          );
        }
        if (detail === "denied" || !current.role.kind) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Access unavailable"
                message="Your role does not allow this action."
              />
            </main>
          );
        }
        if (detail === "unavailable" || !entry) {
          return (
            <main className="access-page">
              <PageNotice
                kind="unavailable"
                title="Role unavailable"
                message="This role could not be loaded. Try again shortly."
              />
            </main>
          );
        }
        return (
          <RoleEditorPage
            key={entry.role.id}
            role={entry.role}
            affectedUsers={entry.affectedUsers}
            onNavigate={navigate}
            onSave={async (draft) => {
              try {
                const { role } = await api.updateRole(entry.role.id, draft, entry.role.revision);
                setEntry((currentEntry) =>
                  currentEntry ? { ...currentEntry, role } : currentEntry,
                );
                return {};
              } catch (error: unknown) {
                if (isSessionExpired(error)) onSessionExpired();
                return { error: accessError(error) };
              }
            }}
            onDelete={async () => {
              try {
                await api.deleteRole(entry.role.id);
                navigate("/roles");
                return {};
              } catch (error: unknown) {
                if (isSessionExpired(error)) onSessionExpired();
                return { error: accessError(error) };
              }
            }}
          />
        );
      }}
    </AccessShell>
  );
}

type AccessSession = { user: AccessUser; role: AccessRole };
type AccessLoadState = "loading" | "ready" | "unavailable";

function useAuthenticationApi(props: AppProps) {
  return useMemo(
    () => new AuthenticationApi(props.csrfToken, props.fetchImpl ?? defaultFetch),
    [props.csrfToken, props.fetchImpl],
  );
}

function useAccessSession(api: AuthenticationApi, onSessionExpired: () => void) {
  const navigation = useContext(NavigationContext);
  const [session, setSession] = useState<AccessSession | null>(null);
  const [sessionState, setSessionState] = useState<AccessLoadState>("loading");

  useEffect(() => {
    if (navigation) return;
    let active = true;
    api.session().then((current) => {
      if (!active) return;
      setSession(current);
      setSessionState("ready");
    }).catch((error: unknown) => {
      if (!active) return;
      if (isSessionExpired(error)) onSessionExpired();
      else setSessionState("unavailable");
    });
    return () => { active = false; };
  }, [api, onSessionExpired, navigation]);

  if (navigation) return { session: navigation.session ?? null, sessionState: navigation.sessionUnavailable ? "unavailable" as const : navigation.session ? "ready" as const : "loading" as const };
  return { session, sessionState };
}

function useRoleReader(api: AuthenticationApi, onSessionExpired: () => void) {
  return useCallback(async (id: string) => {
    try { return (await api.role(id)).role; }
    catch (error: unknown) {
      if (isForbidden(error)) return null;
      if (isSessionExpired(error)) onSessionExpired();
      throw error;
    }
  }, [api, onSessionExpired]);
}

function useAccessRoles(
  api: AuthenticationApi,
  ready: boolean,
  onSessionExpired: () => void,
) {
  const [roles, setRoles] = useState<AccessRole[]>([]);
  const [rolesLimited, setRolesLimited] = useState(false);
  const [rolesState, setRolesState] = useState<AccessLoadState>("loading");

  useEffect(() => {
    if (!ready) return;
    let active = true;
    api.roleOptions().then(({ roles: options }) => {
      if (!active) return;
      setRoles(options);
      setRolesLimited(true);
      setRolesState("ready");
    }).catch((error: unknown) => {
      if (!active) return;
      if (isSessionExpired(error)) onSessionExpired();
      else setRolesState("unavailable");
    });
    return () => { active = false; };
  }, [api, ready, onSessionExpired]);

  return { roles, rolesLimited, rolesState };
}

function useTenantOptions(
  api: AuthenticationApi,
  ready: boolean,
  onSessionExpired: () => void,
) {
  const [tenants, setTenants] = useState<AccessTenant[]>([]);

  useEffect(() => {
    if (!ready) return;
    let active = true;
    api.tenantOptions().then(({ tenants: options }) => {
      if (active) setTenants(options);
    }).catch((error: unknown) => {
      if (active && isSessionExpired(error)) onSessionExpired();
    });
    return () => { active = false; };
  }, [api, ready, onSessionExpired]);

  return tenants;
}

function AccessShell({
  api,
  session,
  sessionState,
  path,
  statusLabel,
  unavailableTitle,
  unavailableMessage,
  children,
}: {
  api: AuthenticationApi;
  session: AccessSession | null;
  sessionState: AccessLoadState;
  path: string;
  statusLabel: string;
  unavailableTitle: string;
  unavailableMessage: string;
  children: (session: AccessSession) => ReactNode;
}) {
  const navigate = useNavigate();
  const [logoutError, setLogoutError] = useState<string>();
  const handleLogout = useCallback(async () => {
    setLogoutError(undefined);
    try {
      await api.logout();
      window.location.assign("/auth/login");
    } catch (error) {
      setLogoutError(accessError(error));
    }
  }, [api]);

  return (
    <AccessFrame
      actor={session?.user}
      role={session?.role}
      path={path}
      onNavigate={navigate}
      onLogout={handleLogout}
    >
      {logoutError ? <div className="access-page"><FormMessage error>{logoutError}</FormMessage></div> : null}
      {session && sessionState === "ready" ? (
        children(session)
      ) : sessionState === "unavailable" ? (
        <main className="access-page">
          <PageNotice kind="unavailable" title={unavailableTitle} message={unavailableMessage} />
        </main>
      ) : (
        <main className="access-page" role="status">{statusLabel}</main>
      )}
    </AccessFrame>
  );
}

function accessError(error: unknown): string {
  return error instanceof Error ? error.message : "The request could not be completed. Try again.";
}

/**
 * Narrows the session payload to a usable principal. Malformed payloads
 * (for example an unrelated JSON document) fall back to legacy ungated UI
 * instead of hiding navigation from every operational page.
 */
function toOperationalSession(value: AccessSession | null): AccessSession | null {
  if (!value || typeof value !== "object") return null;
  const { user, role } = value;
  if (!user || typeof user.email !== "string" || !Array.isArray(user.memberships)) return null;
  if (!role || typeof role.id !== "string" || !Array.isArray(role.grants)) return null;
  return value;
}

function OperationalAccountLinks({ session }: { session: AccessSession | null }) {
  const navigate = useNavigate();
  if (!session) return null;
  const { role } = session;
  const link = (path: string, label: string) => (
    <a
      key={path}
      className="text-sm"
      href={path}
      onClick={(event) => {
        if (shouldInterceptNavigation(event)) {
          event.preventDefault();
          navigate(path);
        }
      }}
    >
      {label}
    </a>
  );
  return (
    <>
      {link("/account", "Account")}
      {canReadUsers(role) ? link("/users", "Users") : null}
      {role.kind ? link("/roles", "Roles") : null}
    </>
  );
}

function ScopedServicesRoute({ platform = false, ...props }: AppProps & { platform?: boolean }) {
  const { tenantKey = "" } = useParams();
  const navigate = useNavigate();
  const api = useAuthenticationApi(props);
  const onSessionExpired = props.onSessionExpired ?? redirectExpiredSession;
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const principal = sessionState === "ready" ? toOperationalSession(session) : null;
  return (
    <ScopedServicesApp
      key={platform ? "platform" : tenantKey}
      {...props}
      scope={platform ? { kind: "platform" } : { kind: "tenant", tenantKey, tenantName: "Tenant" }}
      onNavigate={navigate}
      accessDenied={platform && !!principal && !canReadPlatformServices(principal.role)}
      canEdit={!!principal && (platform
        ? canWritePlatformServices(principal.role)
        : canWriteTenantCredentials(principal.role, membershipAccess(principal.user, tenantKey)))}
      headerActions={
        principal ? (
          <div className="flex flex-wrap items-center gap-2">
            <OperationalAccountLinks session={principal} />
            <SignOut csrfToken={props.csrfToken} />
          </div>
        ) : (
          <SignOut csrfToken={props.csrfToken} />
        )
      }
    />
  );
}

function CallSpecsRoute(props: AppProps) {
  const { tenantKey = "" } = useParams();
  const [searchParams] = useSearchParams();
  return (
    <RoutedApp
      {...props}
      route={{ kind: "call-specs", tenantKey, page: readPage(searchParams) }}
    />
  );
}

function CallsRoute(props: AppProps) {
  const { tenantKey = "" } = useParams();
  const [searchParams] = useSearchParams();
  return (
    <RoutedApp
      {...props}
      route={{
        kind: "calls",
        tenantKey,
        callSpecId: readCallSpecFilter(searchParams),
        page: readPage(searchParams),
      }}
    />
  );
}

function CallDetailsRoute(props: AppProps) {
  const { callId = "", tenantKey = "" } = useParams();
  return <RoutedApp {...props} route={{ kind: "call-details", tenantKey, callId }} />;
}

function ServicesRoute(props: AppProps) {
  const { tenantKey = "" } = useParams();
  return <RoutedApp {...props} route={{ kind: "services", tenantKey }} />;
}

function LegacyPageRedirect() {
  const { pathname, search } = useLocation();
  let path = pathname.replace(/^\/admin(?=\/|$)/, "") || "/";
  path = path.replace(/^\/tenants\/([^/]+)(.*)$/, (_match, key: string, rest: string) => `/t/${key}${rest || "/dashboard"}`);
  if (path.endsWith("/setup-services")) path = path.replace(/\/setup-services$/, "/services");
  if (path === "/onboarding") path = "/getting-started";
  return <Navigate replace to={`${path}${search}`} />;
}

function RoutedApp({
  csrfToken,
  fetchImpl = defaultFetch,
  onSessionExpired = redirectExpiredSession,
  route,
}: AppProps & { route: AdminRoute }) {
  const navigation = useContext(NavigationContext);
  const routerNavigate = useNavigate();
  const api = useAuthenticationApi({ csrfToken, fetchImpl, onSessionExpired });
  const { session, sessionState } = useAccessSession(api, onSessionExpired);
  const principal = sessionState === "ready" ? toOperationalSession(session) : null;
  const tenantKey = "tenantKey" in route ? route.tenantKey : null;
  const searchCallSpecs = useMemo(() => callSpecSearch(fetchImpl, tenantKey ?? "", onSessionExpired), [fetchImpl, tenantKey, onSessionExpired]);
  const tenantAccess =
    principal && tenantKey ? membershipAccess(principal.user, tenantKey) : undefined;
  const capabilities = navigation?.data.tenant?.capabilities;
  const gatedDestinations = capabilities ? [
    ...(capabilities.calls.read ? ["calls" as const] : []),
    ...(capabilities.call_specs.read ? ["call-specs" as const] : []),
    ...(capabilities.services.read || capabilities.api_keys.read ? ["services" as const] : []),
  ] : principal ? workspaceDestinationsFor(principal.role, tenantAccess) : undefined;
  const [tenants, setTenants] = useState<TenantsPageState>({ status: "loading" });
  const [onboarding, setOnboarding] = useState<OnboardingPageState>({
    tenant: { status: "creating", name: "Demo" },
    providers: [],
    samples: { status: "blocked", items: onboardingSamples },
  });
  const [onboardingReload, setOnboardingReload] = useState(0);
  const [callSpecs, setCallSpecs] = useState<TenantCallSpecsPageState>(() => ({
    status: "loading",
    tenant:
      route.kind === "call-specs" ? tenantPlaceholder(route.tenantKey) : tenantPlaceholder(""),
  }));
  const [calls, setCalls] = useState<CallSpecCallsPageState>(() => ({
    status: "loading",
    tenant: route.kind === "calls" ? tenantPlaceholder(route.tenantKey) : tenantPlaceholder(""),
    callSpecs: [],
    callSpecsTruncated: false,
    selectedCallSpecId: route.kind === "calls" ? route.callSpecId : null,
  }));
  const [services, setServices] = useState<TenantServicesPageState>(() => ({
    status: "loading",
    tenant: route.kind === "services" ? tenantPlaceholder(route.tenantKey) : tenantPlaceholder(""),
    setup: { open: false, status: "idle", resultVersion: 0 },
  }));
  const [callDetails, setCallDetails] = useState<CallDetailsPageState>(() => ({
    status: "loading",
    tenant:
      route.kind === "call-details"
        ? tenantPlaceholder(route.tenantKey)
        : tenantPlaceholder(""),
    callSpec: null,
    callSpecRevision: null,
    callId: route.kind === "call-details" ? route.callId : "",
  }));
  const callDetailsControllerRef = useRef<CallDetailsController | undefined>(undefined);
  const routeRef = useRef(route);
  const navigate = useCallback(
    (nextRoute: AdminRoute, replace = false) => {
      routeRef.current = nextRoute;
      routerNavigate(routeUrl(nextRoute), { replace });
    },
    [routerNavigate],
  );
  const submissionRef = useRef<
    { id: number; tenantKey: string; controller: AbortController } | undefined
  >(undefined);
  const submissionSequenceRef = useRef(0);

  useEffect(() => {
    routeRef.current = route;
  }, [route]);

  useEffect(
    () => () => {
      callDetailsControllerRef.current?.dispose();
    },
    [],
  );

  useEffect(() => {
    const submission = submissionRef.current;
    if (
      submission &&
      (route.kind !== "services" || route.tenantKey !== submission.tenantKey)
    ) {
      submission.controller.abort();
      submissionRef.current = undefined;
    }
  }, [route]);

  useEffect(() => {
    if (route.kind !== "tenants") return;
    if (tenants.status !== "ready" || tenants.tenants.length !== 0) return;
    if (sessionState === "loading") return;
    // An empty directory opens onboarding only for principals that may
    // create tenants. Members without assignments would otherwise land on a
    // forbidden onboarding flow; they stay on the empty directory.
    if (principal && !canCreateTenants(principal.role)) return;
    navigate({ kind: "onboarding" }, true);
  }, [route.kind, tenants, principal, sessionState, navigate]);

  useEffect(() => {
    const controller = new AbortController();
    let current = true;
    const isCurrent = () => current;

    if (route.kind === "onboarding") {
      setOnboarding({
        tenant: { status: "creating", name: "Demo" },
        providers: [],
        samples: { status: "blocked", items: onboardingSamples },
      });
      loadOnboarding(csrfToken, controller.signal, fetchImpl, onSessionExpired, isCurrent)
        .then((state) => {
          if (current && state) setOnboarding(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setOnboarding({
              tenant: {
                status: "unavailable",
                name: "Demo",
                message: "The setup endpoint is unavailable. Try again after the Console reconnects.",
              },
              providers: [],
              samples: { status: "blocked", items: onboardingSamples },
            });
          }
        });
    } else if (route.kind === "tenants") {
      setTenants({ status: "loading" });
      loadTenants(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { kind: "tenants", page: 1 } as const;
          navigate(firstPage, true);
        },
      )
        .then((state) => {
          if (current && state) {
            setTenants(state);
          }
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setTenants({
              status: "unavailable",
              message: "Tenant data could not be loaded. Try again after storage is available.",
            });
          }
        });
    } else if (route.kind === "call-specs") {
      setCallSpecs((state) => ({
        status: "loading",
        tenant:
          state.tenant.key === route.tenantKey
            ? state.tenant
            : tenantPlaceholder(route.tenantKey),
      }));

      loadCallSpecs(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { ...route, page: 1 };
          navigate(firstPage, true);
        },
      )
        .then((state) => {
          if (current && state) setCallSpecs(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setCallSpecs((state) => ({
              status: "unavailable",
              tenant: state.tenant,
              message:
                "Call specs could not be loaded. Try again after storage is available.",
            }));
          }
        });
    } else if (route.kind === "calls") {
      setCalls((state) => ({
        status: "loading",
        tenant:
          state.tenant.key === route.tenantKey
            ? state.tenant
            : tenantPlaceholder(route.tenantKey),
        callSpecs: state.tenant.key === route.tenantKey ? state.callSpecs : [],
        callSpecsTruncated:
          state.tenant.key === route.tenantKey
            ? state.callSpecsTruncated
            : false,
        selectedCallSpecId: route.callSpecId,
      }));

      loadCalls(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { ...route, page: 1 };
          navigate(firstPage, true);
        },
      )
        .then((state) => {
          if (current && state) setCalls(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setCalls((state) => ({
              status: "unavailable",
              tenant: state.tenant,
              callSpecs: state.callSpecs,
              callSpecsTruncated: state.callSpecsTruncated,
              selectedCallSpecId: route.callSpecId,
              message: "Calls could not be loaded. Try again after storage is available.",
            }));
          }
        });
    } else if (route.kind === "services") {
      setServices((state) => ({
        status: "loading",
        tenant:
          state.tenant.key === route.tenantKey
            ? state.tenant
            : tenantPlaceholder(route.tenantKey),
        setup: { open: false, status: "idle", resultVersion: state.setup.resultVersion },
      }));

      loadServices(route, controller.signal, fetchImpl, onSessionExpired, isCurrent)
        .then((state) => {
          if (current && state) setServices(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setServices((state) => ({
              status: "unavailable",
              tenant: state.tenant,
              setup: state.setup,
              message: "Services could not be loaded. Try again after storage is available.",
            }));
          }
        });
    } else {
      callDetailsControllerRef.current?.dispose();
      callDetailsControllerRef.current = undefined;
      setCallDetails({
        status: "loading",
        tenant: tenantPlaceholder(route.tenantKey),
        callSpec: null,
        callSpecRevision: null,
        callId: route.callId,
      });

      loadCallDetails(route, controller.signal, fetchImpl, onSessionExpired, isCurrent)
        .then((result) => {
          if (!current || !result) return;
          if (result.controller) callDetailsControllerRef.current = result.controller;
          setCallDetails(result.state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setCallDetails({
              status: "unavailable",
              tenant: tenantPlaceholder(route.tenantKey),
              callSpec: null,
              callSpecRevision: null,
              callId: route.callId,
              message: "Call inspection is unavailable. Try again after storage is available.",
            });
          }
        });
    }

    return () => {
      current = false;
      controller.abort();
      if (route.kind === "call-details") {
        callDetailsControllerRef.current?.dispose();
        callDetailsControllerRef.current = undefined;
      }
    };
  }, [
    csrfToken,
    fetchImpl,
    navigate,
    onSessionExpired,
    route,
    onboardingReload,
  ]);

  const headerActions = principal ? (
    <div className="flex flex-wrap items-center gap-2">
      <OperationalAccountLinks session={principal} />
      {canReadPlatformServices(principal.role) ? (
        <a className="text-sm" href="/admin/platform/services">Platform services</a>
      ) : null}
      <SignOut csrfToken={csrfToken} />
    </div>
  ) : (
    <div className="flex flex-wrap items-center gap-2">
      <SignOut csrfToken={csrfToken} />
    </div>
  );
  // Privileged destinations stay hidden until the server principal arrives;
  // falling back to the full list would flash Services to read-only members.
  // Privileged destinations stay hidden until the server principal arrives;
  // falling back to the full list would flash Services to read-only members.
  if (route.kind === "onboarding") {
    return (
      <OnboardingPage
        onRetry={() => setOnboardingReload((version) => version + 1)}
        onInstallSamples={() =>
          installOnboardingSamples(
            onboarding,
            csrfToken,
            fetchImpl,
            onSessionExpired,
            setOnboarding,
          )
        }
        onManageServices={
          onboarding.tenant.status === "ready"
            ? () => {
                if (onboarding.tenant.status === "ready")
                  routerNavigate(
                    `/admin/tenants/${encodeURIComponent(onboarding.tenant.key)}/services`,
                  );
              }
            : undefined
        }
        state={onboarding}
      />
    );
  }

  if (route.kind === "call-details") {
    return (
      <CallDetailsPage
        state={callDetails}
      />
    );
  }

  if (route.kind === "call-specs") {
    const canCreate = capabilities ? capabilities.call_specs.write : !!principal && canCreateCallSpecs(principal.role, tenantAccess);
    return (
      <TenantCallSpecsPage
        onNewCallSpec={canCreate ? () => routerNavigate(`/admin/tenants/${encodeURIComponent(route.tenantKey)}/call-specs/new`) : undefined}
        onEditCallSpec={(id) => routerNavigate(`/admin/tenants/${encodeURIComponent(route.tenantKey)}/call-specs/${encodeURIComponent(id)}`)}
        headerActions={headerActions}
        linkCalls
        onNextPage={() => navigate({ ...route, page: route.page + 1 })}
        onPreviousPage={() => navigate({ ...route, page: Math.max(1, route.page - 1) })}
        onSelectCallSpec={(callSpecId) =>
          navigate({ kind: "calls", tenantKey: route.tenantKey, callSpecId, page: 1 })
        }
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        onSelectWorkspace={(destination) => {
          if (destination === "calls") {
            navigate({ kind: "calls", tenantKey: route.tenantKey, callSpecId: null, page: 1 });
          } else if (destination === "services") {
            navigate({ kind: "services", tenantKey: route.tenantKey });
          }
        }}
        state={callSpecs}
        workspaceDestinations={gatedDestinations ?? []}
      />
    );
  }

  if (route.kind === "calls") {
    return (
      <CallSpecCallsPage
        searchCallSpecs={searchCallSpecs}
        headerActions={headerActions}
        linkCallDetails
        onNextPage={() => navigate({ ...route, page: route.page + 1 })}
        onPreviousPage={() => navigate({ ...route, page: Math.max(1, route.page - 1) })}
        onSelectCallSpec={(callSpecId) =>
          navigate({ ...route, callSpecId, page: 1 })
        }
        onSelectTenant={() =>
          navigate({ kind: "call-specs", tenantKey: route.tenantKey, page: 1 })
        }
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        onSelectWorkspace={(destination) => {
          if (destination === "call-specs") {
            navigate({ kind: "call-specs", tenantKey: route.tenantKey, page: 1 });
          } else if (destination === "services") {
            navigate({ kind: "services", tenantKey: route.tenantKey });
          }
        }}
        state={calls}
        workspaceDestinations={gatedDestinations ?? []}
      />
    );
  }

  if (route.kind === "services") {
    return (
      <TenantServicesPage
        headerActions={headerActions}
        canReadCredentials={navigation?.data.tenant?.capabilities.api_keys.read ?? false}
        canConnect={capabilities ? capabilities.api_keys.write : principal ? canWriteTenantCredentials(principal.role, tenantAccess) : false}
        onCreateCredential={(draft) =>
          saveCredential(
            route.tenantKey,
            draft,
            undefined,
            csrfToken,
            fetchImpl,
            onSessionExpired,
            setServices,
            routeRef,
            submissionRef,
            submissionSequenceRef,
          )
        }
        onUpdateCredential={(service, draft) =>
          saveCredential(
            route.tenantKey,
            draft,
            service,
            csrfToken,
            fetchImpl,
            onSessionExpired,
            setServices,
            routeRef,
            submissionRef,
            submissionSequenceRef,
          )
        }
        onTestCredential={(draft) =>
          testCredentialRequest(
            `/api/tenants/${encodeURIComponent(route.tenantKey)}/credentials/test`,
            draft,
            undefined,
            csrfToken,
            fetchImpl,
            onSessionExpired,
          )
        }
        onDismissCredential={() => {
          submissionRef.current?.controller.abort();
          submissionRef.current = undefined;
          setServices((state) => ({
            ...state,
            setup: {
              open: false,
              status: "idle",
              resultVersion: state.setup.resultVersion,
            },
          }));
        }}
        onSelectTenant={() =>
          navigate({ kind: "call-specs", tenantKey: route.tenantKey, page: 1 })
        }
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        onSelectWorkspace={(destination) => {
          if (destination === "call-specs") {
            navigate({ kind: "call-specs", tenantKey: route.tenantKey, page: 1 });
          } else if (destination === "calls") {
            navigate({ kind: "calls", tenantKey: route.tenantKey, callSpecId: null, page: 1 });
          }
        }}
        state={services}
        workspaceDestinations={gatedDestinations ?? []}
      />
    );
  }

  return (
    <TenantsPage
      headerActions={headerActions}
      onNextPage={() => navigate({ kind: "tenants", page: route.page + 1 })}
      onPreviousPage={() => navigate({ kind: "tenants", page: Math.max(1, route.page - 1) })}
      onSelectTenant={(tenantKey) => navigate({ kind: "call-specs", tenantKey, page: 1 })}
      state={tenants}
    />
  );
}

async function loadTenants(
  selected: Extract<AdminRoute, { kind: "tenants" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
  recoverFirstPage: () => void,
): Promise<TenantsPageState | undefined> {
  const response = await fetchImpl(`/api/tenants?page=${selected.page}`, {
    headers: { accept: "application/json" },
    signal,
  });

  if (!isCurrent()) return;

  if (response.status === 401) {
    onSessionExpired();
    return;
  }

  if (response.status === 422 && selected.page !== 1) {
    recoverFirstPage();
    return;
  }

  if (!response.ok) throw new Error("Tenant directory unavailable");
  const result = parseTenantPage(await response.json());
  if (!isCurrent()) return;

  return {
    status: "ready",
    tenants: result.tenants,
    pagination: paginationModel(result.pagination),
  };
}

async function loadOnboarding(
  csrfToken: string,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
): Promise<OnboardingPageState | undefined> {
  const tenantResponse = await fetchImpl("/admin/api/onboarding/demo-tenant", {
    method: "POST",
    headers: {
      accept: "application/json",
      "x-csrf-token": csrfToken,
    },
    signal,
  });

  if (!isCurrent()) return;
  if (tenantResponse.status === 401) {
    onSessionExpired();
    return;
  }
  if (!tenantResponse.ok) throw new Error("Demo tenant unavailable");
  const tenant = parseDemoTenant(await tenantResponse.json());

  const serviceResponse = await fetchImpl(
    `/api/tenants/${encodeURIComponent(tenant.key)}/service-bindings`,
    { headers: { accept: "application/json" }, signal },
  );

  if (!isCurrent()) return;
  if (serviceResponse.status === 401) {
    onSessionExpired();
    return;
  }
  if (!serviceResponse.ok) throw new Error("Demo tenant services unavailable");
  const directory = parseBindingDirectory(await serviceResponse.json(), {
    kind: "tenant",
    tenantKey: tenant.key,
    tenantName: tenant.name,
  });

  const providers = directory.bindings.flatMap((service) =>
    service.provider === "vertex_ai" || service.name !== service.provider
      ? []
      : [
          onboardingProvider(
            service.provider,
            service.status === "connected" ? "valid" : service.status,
            {
              lastValidatedAt: service.lastValidatedAt,
              source: service.source,
              message:
                service.status === "unavailable"
                  ? "Service unavailable. Open Manage services to check its configuration."
                  : undefined,
            },
          ),
        ],
  );

  return {
    tenant: { status: "ready", key: tenant.key, name: tenant.name },
    providers,
    samples: {
      status: samplePrerequisitesMet(providers) ? "ready" : "blocked",
      items: onboardingSamples,
    },
  };
}

function samplePrerequisitesMet(providers: OnboardingPageState["providers"]) {
  const valid = new Set(
    providers
      .filter((provider) => provider.status === "valid")
      .map((provider) => provider.provider),
  );
  return valid.has("deepgram") && (valid.has("google") || valid.has("zenmux"));
}

async function installOnboardingSamples(
  current: OnboardingPageState,
  csrfToken: string,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  setOnboarding: Dispatch<SetStateAction<OnboardingPageState>>,
) {
  if (current.tenant.status !== "ready") return;
  setOnboarding((state) => ({
    ...state,
    samples: { ...state.samples, status: "loading", message: undefined },
  }));

  try {
    const response = await fetchImpl("/admin/api/onboarding/demo-tenant/samples", {
      method: "POST",
      headers: {
        accept: "application/json",
        "x-csrf-token": csrfToken,
      },
    });

    if (response.status === 401) {
      onSessionExpired();
      return;
    }

    if (response.status === 422) {
      throw new Error("Sample prerequisites missing");
    }
    if (!response.ok) throw new Error("Sample installation unavailable");

    const items = parseInstalledSamples(await response.json());
    const complete = items.every((sample) => sample.status === "installed");
    setOnboarding((state) => ({
      ...state,
      samples: {
        status: complete ? "complete" : "error",
        items,
        message: complete
          ? undefined
          : "Some sample call specs were not installed. Existing edited specs were preserved.",
      },
    }));
  } catch {
    setOnboarding((state) => ({
      ...state,
      samples: {
        ...state.samples,
        status: "error",
        message: "Sample call specs could not be loaded. Check the required services and retry.",
      },
    }));
  }
}

async function loadCallSpecs(
  selected: Extract<AdminRoute, { kind: "call-specs" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
  recoverFirstPage: () => void,
): Promise<TenantCallSpecsPageState | undefined> {
  const encodedTenant = encodeURIComponent(selected.tenantKey);
  const response = await fetchImpl(
    `/api/tenants/${encodedTenant}/call-specs?page=${selected.page}`,
    { headers: { accept: "application/json" }, signal },
  );

  if (!isCurrent()) return;

  if (response.status === 401) {
    onSessionExpired();
    return;
  }

  if (response.status === 422 && selected.page !== 1) {
    recoverFirstPage();
    return;
  }

  if (response.status === 404) {
    return {
      status: "unavailable",
      tenant: tenantPlaceholder(selected.tenantKey),
      message: "This tenant could not be found.",
    };
  }

  if (!response.ok) throw new Error("Call spec directory unavailable");
  const result = parseCallSpecPage(await response.json());
  if (!isCurrent()) return;
  if (result.tenant.key !== selected.tenantKey) throw new Error("Unexpected tenant response");

  return {
    status: "ready",
    tenant: result.tenant,
    callSpecs: result.callSpecs,
    pagination: paginationModel(result.pagination),
  };
}

async function loadCalls(
  selected: Extract<AdminRoute, { kind: "calls" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
  recoverFirstPage: () => void,
): Promise<CallSpecCallsPageState | undefined> {
  const encodedTenant = encodeURIComponent(selected.tenantKey);
  const query = new URLSearchParams({ page: String(selected.page) });
  if (selected.callSpecId) query.set("call_spec_id", selected.callSpecId);

  const response = await fetchImpl(
    `/admin/api/tenants/${encodedTenant}/calls?${query.toString()}`,
    { headers: { accept: "application/json" }, signal },
  );

  if (!isCurrent()) return;

  if (response.status === 401) {
    onSessionExpired();
    return;
  }

  if (response.status === 422 && selected.page !== 1) {
    recoverFirstPage();
    return;
  }

  if (response.status === 404) {
    return {
      status: "unavailable",
      tenant: tenantPlaceholder(selected.tenantKey),
      callSpecs: [],
      callSpecsTruncated: false,
      selectedCallSpecId: selected.callSpecId,
      message: "This tenant or call spec could not be found.",
    };
  }

  if (!response.ok) throw new Error("Call directory unavailable");
  const result = parseCallPage(await response.json());
  if (!isCurrent()) return;
  if (result.tenant.key !== selected.tenantKey) throw new Error("Unexpected tenant response");
  if (result.selectedCallSpecId !== selected.callSpecId) {
    throw new Error("Unexpected call filter response");
  }

  return {
    status: "ready",
    tenant: result.tenant,
    callSpecs: result.callSpecs,
    callSpecsTruncated: result.callSpecsTruncated,
    selectedCallSpecId: result.selectedCallSpecId,
    calls: result.calls,
    pagination: paginationModel(result.pagination),
  };
}

async function loadServices(
  selected: Extract<AdminRoute, { kind: "services" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
): Promise<TenantServicesPageState | undefined> {
  const encodedTenant = encodeURIComponent(selected.tenantKey);
  const response = await fetchImpl(`/api/tenants/${encodedTenant}/services`, {
    headers: { accept: "application/json" },
    signal,
  });

  if (!isCurrent()) return;
  if (response.status === 401) {
    onSessionExpired();
    return;
  }
  if (response.status === 404) {
    return {
      status: "unavailable",
      tenant: tenantPlaceholder(selected.tenantKey),
      setup: { open: false, status: "idle", resultVersion: 0 },
      message: "This tenant could not be found.",
    };
  }
  if (!response.ok) throw new Error("Service directory unavailable");

  const result = parseServiceDirectory(await response.json());
  if (!isCurrent()) return;
  if (result.tenant.key !== selected.tenantKey) throw new Error("Unexpected tenant response");

  return {
    status: "ready",
    tenant: result.tenant,
    services: result.services,
    truncated: result.truncated,
    setup: { open: false, status: "idle", resultVersion: 0 },
  };
}

async function loadCallDetails(
  selected: Extract<AdminRoute, { kind: "call-details" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
): Promise<
  | { state: CallDetailsPageState; controller?: CallDetailsController }
  | undefined
> {
  let result: AdminCallDetails;
  try {
    result = await requestCallDetails(selected, signal, fetchImpl);
  } catch (error: unknown) {
    if (!isCurrent()) return;
    if (error instanceof AdminCallDetailsError && error.kind === "expired") {
      onSessionExpired();
      return;
    }

    const context = {
      tenant: tenantPlaceholder(selected.tenantKey),
      callSpec: null,
      callSpecRevision: null,
      callId: selected.callId,
    };

    if (error instanceof AdminCallDetailsError && error.kind === "missing") {
      return {
        state: {
          status: "unavailable",
          ...context,
          message: "This call could not be found.",
        },
      };
    }
    if (error instanceof AdminCallDetailsError && error.kind === "malformed") {
      return {
        state: {
          status: "malformed",
          ...context,
          message: "The inspection response did not match the supported call-details schema.",
        },
      };
    }
    throw error;
  }

  if (!isCurrent()) return;
  validateCallDetailsIdentity(result, selected);

  const loader: CallDetailsLoader = {
    refresh: async (refreshSignal) => {
      try {
        const refreshed = await requestCallDetails(selected, refreshSignal, fetchImpl);
        validateCallDetailsIdentity(refreshed, selected);
        return refreshed.snapshot;
      } catch (error: unknown) {
        if (
          error instanceof AdminCallDetailsError &&
          error.kind === "expired" &&
          !refreshSignal.aborted
        ) {
          onSessionExpired();
        }
        throw error;
      }
    },
  };
  const store = createCallDetailsStore(result.snapshot);
  const controller = createCallDetailsController({ store, loader });

  return {
    controller,
    state: {
      status: "ready",
      tenant: result.tenant,
      callSpec: result.callSpec,
      callSpecRevision: result.callSpecRevision,
      callId: selected.callId,
      controller: { details: controller, history: controller },
      completeness: result.snapshot.completeness.state,
    },
  };
}

async function requestCallDetails(
  selected: Extract<AdminRoute, { kind: "call-details" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
) {
  const response = await fetchImpl(
    `/admin/api/tenants/${encodeURIComponent(selected.tenantKey)}/calls/${encodeURIComponent(selected.callId)}`,
    { headers: { accept: "application/json" }, signal },
  );

  if (response.status === 401) {
    throw new AdminCallDetailsError("expired");
  }
  if (response.status === 404) throw new AdminCallDetailsError("missing");
  if (!response.ok) throw new AdminCallDetailsError("unavailable");

  try {
    return parseAdminCallDetails(await response.json());
  } catch (error: unknown) {
    signal.throwIfAborted();
    throw new AdminCallDetailsError("malformed", { cause: error });
  }
}

function validateCallDetailsIdentity(
  result: AdminCallDetails,
  selected: Extract<AdminRoute, { kind: "call-details" }>,
) {
  if (
    result.tenant.key !== selected.tenantKey ||
    result.snapshot.call.id !== selected.callId
  ) {
    throw new AdminCallDetailsError("malformed");
  }
}

class AdminCallDetailsError extends Error {
  constructor(
    readonly kind: "expired" | "missing" | "malformed" | "unavailable",
    options?: ErrorOptions,
  ) {
    super(`Admin call details ${kind}`, options);
    this.name = "AdminCallDetailsError";
  }
}

async function saveCredential(
  tenantKey: string,
  draft: CredentialDraft,
  existing: ServiceInventoryItem | undefined,
  csrfToken: string,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  setServices: Dispatch<SetStateAction<TenantServicesPageState>>,
  routeRef: MutableRefObject<AdminRoute>,
  submissionRef: MutableRefObject<
    { id: number; tenantKey: string; controller: AbortController } | undefined
  >,
  submissionSequenceRef: MutableRefObject<number>,
) {
  submissionRef.current?.controller.abort();
  const controller = new AbortController();
  const id = ++submissionSequenceRef.current;
  submissionRef.current = { id, tenantKey, controller };

  setServices((state) => ({
    ...state,
    setup: {
      open: true,
      status: "submitting",
      resultVersion: state.setup.resultVersion,
    },
  }));

  try {
    const encodedTenant = encodeURIComponent(tenantKey);
    const credentialPath = existing
      ? `/credentials/${encodeURIComponent(existing.credentialId)}`
      : "/credentials";
    const response = await fetchImpl(`/api/tenants/${encodedTenant}${credentialPath}`, {
      method: existing ? "PATCH" : "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify(credentialRequest(draft)),
      signal: controller.signal,
    });

    if (!currentSubmission(id, tenantKey, routeRef, submissionRef)) return;
    if (response.status === 401) {
      onSessionExpired();
      return;
    }
    if (!existing && response.status === 409) {
      setServices((state) => ({
        ...state,
        setup: {
          open: true,
          status: "conflict",
          resultVersion: state.setup.resultVersion,
          message: "A credential for this provider already exists.",
        },
      }));
      return;
    }
    if (response.status === 422) {
      setServices((state) => ({
        ...state,
        setup: {
          open: true,
          status: "validation",
          resultVersion: state.setup.resultVersion,
          message: "Enter valid provider credentials.",
        },
      }));
      return;
    }
    if (!response.ok) throw new Error("Credential store unavailable");
    const stored = parseCreatedCredential(await response.json());
    if (!currentSubmission(id, tenantKey, routeRef, submissionRef)) return;

    setServices((state) =>
      state.status === "ready"
        ? {
            ...state,
            services: (existing
              ? state.services.map((service) =>
                  service.credentialId === existing.credentialId ? stored : service,
                )
              : [...state.services, stored]
            ).sort(compareServices),
            setup: {
              open: false,
              status: "success",
              resultVersion: state.setup.resultVersion + 1,
            },
          }
        : state,
    );
  } catch (error: unknown) {
    if (!aborted(error) && currentSubmission(id, tenantKey, routeRef, submissionRef)) {
      setServices((state) => ({
        ...state,
        setup: {
          open: true,
          status: "error",
          resultVersion: state.setup.resultVersion,
          message: "Credential could not be stored.",
        },
      }));
    }
  } finally {
    if (submissionRef.current?.id === id) submissionRef.current = undefined;
  }
}

function compareServices(
  left: Extract<TenantServicesPageState, { status: "ready" }>["services"][number],
  right: Extract<TenantServicesPageState, { status: "ready" }>["services"][number],
) {
  return (
    left.provider.localeCompare(right.provider) ||
    left.name.localeCompare(right.name) ||
    left.id.localeCompare(right.id)
  );
}

function currentSubmission(
  id: number,
  tenantKey: string,
  routeRef: MutableRefObject<AdminRoute>,
  submissionRef: MutableRefObject<
    { id: number; tenantKey: string; controller: AbortController } | undefined
  >,
) {
  const route = routeRef.current;
  return (
    submissionRef.current?.id === id &&
    route.kind === "services" &&
    route.tenantKey === tenantKey
  );
}

function SignOut({ csrfToken }: { csrfToken: string }) {
  return (
    <form action="/auth/logout" method="post">
      <input type="hidden" name="_csrf_token" value={csrfToken} />
      <button
        type="submit"
        className="min-h-9 rounded-md px-3 text-sm font-medium text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)]"
      >
        Sign out
      </button>
    </form>
  );
}

function routeUrl(route: AdminRoute) {
  const query = new URLSearchParams();
  if (
    route.kind !== "onboarding" &&
    route.kind !== "services" &&
    route.kind !== "call-details" &&
    route.page !== 1
  ) {
    query.set("page", String(route.page));
  }
  if (route.kind === "calls" && route.callSpecId) {
    query.set("call_spec_id", route.callSpecId);
  }
  const suffix = query.size > 0 ? `?${query.toString()}` : "";

  if (route.kind === "onboarding") return "/getting-started";
  if (route.kind === "tenants") return `/tenants${suffix}`;
  const tenant = encodeURIComponent(route.tenantKey);
  if (route.kind === "call-details") {
    return `/admin/tenants/${tenant}/calls/${encodeURIComponent(route.callId)}`;
  }
  return `/t/${tenant}/${route.kind}${suffix}`;
}

function readPage(searchParams: URLSearchParams) {
  const raw = searchParams.get("page");
  if (raw === null) return 1;
  const page = Number(raw);
  return Number.isSafeInteger(page) && page > 0 ? page : 1;
}

function readCallSpecFilter(searchParams: URLSearchParams) {
  const callSpecId = searchParams.get("call_spec_id");
  return callSpecId && callSpecId.length <= 256 ? callSpecId : null;
}

function tenantPlaceholder(key: string) {
  return { key, name: key || "Tenant" };
}

function aborted(error: unknown) {
  return error instanceof DOMException && error.name === "AbortError";
}

function paginationModel({
  page,
  pageSize,
  total,
  totalPages,
}: {
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
}): PaginationModel | null {
  if (totalPages <= 1) return null;

  const first = (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);

  return {
    label: `${first}–${last} of ${total}`,
    hasPrevious: page > 1,
    hasNext: page < totalPages,
  };
}
