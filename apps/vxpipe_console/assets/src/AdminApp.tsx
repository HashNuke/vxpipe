import {
  useEffect,
  useRef,
  useState,
  type Dispatch,
  type MutableRefObject,
  type SetStateAction,
} from "react";
import {
  createCallDetailsController,
  createCallDetailsStore,
  type CallDetailsController,
  type CallDetailsLoader,
} from "@vxpipe/core";

import {
  parseCallPage,
  parseCreatedCredential,
  parseDefinitionPage,
  parseServiceDirectory,
  parseTenantPage,
} from "./admin/adminApi";
import { DefinitionCallsPage } from "./admin/DefinitionCallsPage";
import { CallDetailsPage } from "./admin/CallDetailsPage";
import {
  parseAdminCallDetails,
  type AdminCallDetails,
} from "./admin/adminCallDetailsApi";
import type { CallDetailsPageState } from "./admin/callDetailsTypes";
import type { DefinitionCallsPageState } from "./admin/callTypes";
import { TenantDefinitionsPage } from "./admin/TenantDefinitionsPage";
import type { TenantDefinitionsPageState } from "./admin/definitionTypes";
import type {
  CredentialDraft,
  ServiceInventoryItem,
  TenantServicesPageState,
} from "./admin/serviceTypes";
import { TenantServicesPage } from "./admin/TenantServicesPage";
import { TenantsPage } from "./admin/TenantsPage";
import type { PaginationModel, TenantsPageState } from "./admin/tenantTypes";

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type AdminRoute =
  | { kind: "tenants"; page: number }
  | { kind: "definitions"; tenantKey: string; page: number }
  | { kind: "calls"; tenantKey: string; definitionId: string | null; page: number }
  | { kind: "call-details"; tenantKey: string; callId: string }
  | { kind: "services"; tenantKey: string };

const defaultFetch: Fetch = (input, init) => window.fetch(input, init);
const redirectExpiredSession = () => window.location.assign("/auth/login");

export function AdminApp({
  csrfToken,
  fetchImpl = defaultFetch,
  onSessionExpired = redirectExpiredSession,
}: {
  csrfToken: string;
  fetchImpl?: Fetch;
  onSessionExpired?: () => void;
}) {
  const [route, setRoute] = useState(readRoute);
  const [tenants, setTenants] = useState<TenantsPageState>({ status: "loading" });
  const [definitions, setDefinitions] = useState<TenantDefinitionsPageState>(() => ({
    status: "loading",
    tenant:
      route.kind === "definitions" ? tenantPlaceholder(route.tenantKey) : tenantPlaceholder(""),
  }));
  const [calls, setCalls] = useState<DefinitionCallsPageState>(() => ({
    status: "loading",
    tenant: route.kind === "calls" ? tenantPlaceholder(route.tenantKey) : tenantPlaceholder(""),
    definitions: [],
    definitionOptionsTruncated: false,
    selectedDefinitionId: route.kind === "calls" ? route.definitionId : null,
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
    definition: null,
    definitionRevision: null,
    callId: route.kind === "call-details" ? route.callId : "",
  }));
  const callDetailsControllerRef = useRef<CallDetailsController | undefined>(undefined);
  const routeRef = useRef(route);
  const submissionRef = useRef<
    { id: number; tenantKey: string; controller: AbortController } | undefined
  >(undefined);
  const submissionSequenceRef = useRef(0);

  useEffect(() => {
    const restore = () => {
      const restored = readRoute();
      routeRef.current = restored;
      setRoute(restored);
    };
    window.addEventListener("popstate", restore);
    return () => window.removeEventListener("popstate", restore);
  }, []);

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
    const controller = new AbortController();
    let current = true;
    const isCurrent = () => current;

    if (route.kind === "tenants") {
      setTenants({ status: "loading" });
      loadTenants(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { kind: "tenants", page: 1 } as const;
          window.history.replaceState({}, "", routeUrl(firstPage));
          setRoute(firstPage);
        },
      )
        .then((state) => {
          if (current && state) setTenants(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setTenants({
              status: "unavailable",
              message: "Tenant data could not be loaded. Try again after storage is available.",
            });
          }
        });
    } else if (route.kind === "definitions") {
      setDefinitions((state) => ({
        status: "loading",
        tenant:
          state.tenant.key === route.tenantKey
            ? state.tenant
            : tenantPlaceholder(route.tenantKey),
      }));

      loadDefinitions(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { ...route, page: 1 };
          window.history.replaceState({}, "", routeUrl(firstPage));
          setRoute(firstPage);
        },
      )
        .then((state) => {
          if (current && state) setDefinitions(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setDefinitions((state) => ({
              status: "unavailable",
              tenant: state.tenant,
              message:
                "Call definitions could not be loaded. Try again after storage is available.",
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
        definitions: state.tenant.key === route.tenantKey ? state.definitions : [],
        definitionOptionsTruncated:
          state.tenant.key === route.tenantKey
            ? state.definitionOptionsTruncated
            : false,
        selectedDefinitionId: route.definitionId,
      }));

      loadCalls(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { ...route, page: 1 };
          window.history.replaceState({}, "", routeUrl(firstPage));
          setRoute(firstPage);
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
              definitions: state.definitions,
              definitionOptionsTruncated: state.definitionOptionsTruncated,
              selectedDefinitionId: route.definitionId,
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
        definition: null,
        definitionRevision: null,
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
              definition: null,
              definitionRevision: null,
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
  }, [fetchImpl, onSessionExpired, route]);

  function navigate(nextRoute: AdminRoute, replace = false) {
    window.history[replace ? "replaceState" : "pushState"]({}, "", routeUrl(nextRoute));
    routeRef.current = nextRoute;
    setRoute(nextRoute);
  }

  const headerActions = <SignOut csrfToken={csrfToken} />;
  const workspaceDestinations = ["definitions", "calls", "services"] as const;

  if (route.kind === "call-details") {
    return (
      <CallDetailsPage
        state={callDetails}
      />
    );
  }

  if (route.kind === "definitions") {
    return (
      <TenantDefinitionsPage
        headerActions={headerActions}
        linkCalls
        onNextPage={() => navigate({ ...route, page: route.page + 1 })}
        onPreviousPage={() => navigate({ ...route, page: Math.max(1, route.page - 1) })}
        onSelectDefinition={(definitionId) =>
          navigate({ kind: "calls", tenantKey: route.tenantKey, definitionId, page: 1 })
        }
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        onSelectWorkspace={(destination) => {
          if (destination === "calls") {
            navigate({ kind: "calls", tenantKey: route.tenantKey, definitionId: null, page: 1 });
          } else if (destination === "services") {
            navigate({ kind: "services", tenantKey: route.tenantKey });
          }
        }}
        state={definitions}
        workspaceDestinations={[...workspaceDestinations]}
      />
    );
  }

  if (route.kind === "calls") {
    return (
      <DefinitionCallsPage
        headerActions={headerActions}
        linkCallDetails
        onNextPage={() => navigate({ ...route, page: route.page + 1 })}
        onPreviousPage={() => navigate({ ...route, page: Math.max(1, route.page - 1) })}
        onSelectDefinition={(definitionId) =>
          navigate({ ...route, definitionId, page: 1 })
        }
        onSelectTenant={() =>
          navigate({ kind: "definitions", tenantKey: route.tenantKey, page: 1 })
        }
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        onSelectWorkspace={(destination) => {
          if (destination === "definitions") {
            navigate({ kind: "definitions", tenantKey: route.tenantKey, page: 1 });
          } else if (destination === "services") {
            navigate({ kind: "services", tenantKey: route.tenantKey });
          }
        }}
        state={calls}
        workspaceDestinations={[...workspaceDestinations]}
      />
    );
  }

  if (route.kind === "services") {
    return (
      <TenantServicesPage
        headerActions={headerActions}
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
          navigate({ kind: "definitions", tenantKey: route.tenantKey, page: 1 })
        }
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        onSelectWorkspace={(destination) => {
          if (destination === "definitions") {
            navigate({ kind: "definitions", tenantKey: route.tenantKey, page: 1 });
          } else if (destination === "calls") {
            navigate({ kind: "calls", tenantKey: route.tenantKey, definitionId: null, page: 1 });
          }
        }}
        state={services}
        workspaceDestinations={[...workspaceDestinations]}
      />
    );
  }

  return (
    <TenantsPage
      headerActions={headerActions}
      onNextPage={() => navigate({ kind: "tenants", page: route.page + 1 })}
      onPreviousPage={() => navigate({ kind: "tenants", page: Math.max(1, route.page - 1) })}
      onSelectTenant={(tenantKey) => navigate({ kind: "definitions", tenantKey, page: 1 })}
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
  const response = await fetchImpl(`/admin/api/tenants?page=${selected.page}`, {
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

async function loadDefinitions(
  selected: Extract<AdminRoute, { kind: "definitions" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
  recoverFirstPage: () => void,
): Promise<TenantDefinitionsPageState | undefined> {
  const encodedTenant = encodeURIComponent(selected.tenantKey);
  const response = await fetchImpl(
    `/admin/api/tenants/${encodedTenant}/definitions?page=${selected.page}`,
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

  if (!response.ok) throw new Error("Definition directory unavailable");
  const result = parseDefinitionPage(await response.json());
  if (!isCurrent()) return;
  if (result.tenant.key !== selected.tenantKey) throw new Error("Unexpected tenant response");

  return {
    status: "ready",
    tenant: result.tenant,
    definitions: result.definitions,
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
): Promise<DefinitionCallsPageState | undefined> {
  const encodedTenant = encodeURIComponent(selected.tenantKey);
  const query = new URLSearchParams({ page: String(selected.page) });
  if (selected.definitionId) query.set("definition_id", selected.definitionId);

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
      definitions: [],
      definitionOptionsTruncated: false,
      selectedDefinitionId: selected.definitionId,
      message: "This tenant or call definition could not be found.",
    };
  }

  if (!response.ok) throw new Error("Call directory unavailable");
  const result = parseCallPage(await response.json());
  if (!isCurrent()) return;
  if (result.tenant.key !== selected.tenantKey) throw new Error("Unexpected tenant response");
  if (result.selectedDefinitionId !== selected.definitionId) {
    throw new Error("Unexpected call filter response");
  }

  return {
    status: "ready",
    tenant: result.tenant,
    definitions: result.definitions,
    definitionOptionsTruncated: result.definitionsTruncated,
    selectedDefinitionId: result.selectedDefinitionId,
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
  const response = await fetchImpl(`/admin/api/tenants/${encodedTenant}/services`, {
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
      definition: null,
      definitionRevision: null,
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
      definition: result.definition,
      definitionRevision: result.definitionRevision,
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
    const response = await fetchImpl(`/admin/api/tenants/${encodedTenant}${credentialPath}`, {
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

function credentialRequest(draft: CredentialDraft) {
  if ("apiKey" in draft.values) {
    return {
      provider: draft.provider,
      values: { api_key: draft.values.apiKey },
    };
  }

  return {
    provider: draft.provider,
    values: {
      account_sid: draft.values.accountSid,
      auth_token: draft.values.authToken,
    },
  };
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

function readRoute(): AdminRoute {
  const page = readPage();
  const detailsMatch = window.location.pathname.match(
    /^\/admin\/tenants\/([^/]+)\/calls\/([^/]+)\/?$/,
  );

  if (detailsMatch) {
    try {
      return {
        kind: "call-details",
        tenantKey: decodeURIComponent(detailsMatch[1]),
        callId: decodeURIComponent(detailsMatch[2]),
      };
    } catch {
      return { kind: "tenants", page: 1 };
    }
  }

  const match = window.location.pathname.match(
    /^\/admin\/tenants\/([^/]+)(?:\/(definitions|calls|services))?\/?$/,
  );

  if (!match) return { kind: "tenants", page };

  try {
    const tenantKey = decodeURIComponent(match[1]);
    const destination = match[2];

    if (destination === "calls") {
      return {
        kind: "calls",
        tenantKey,
        definitionId: readDefinitionFilter(),
        page,
      };
    }

    if (destination === "services") return { kind: "services", tenantKey };

    const route = { kind: "definitions", tenantKey, page } as const;
    if (!destination) window.history.replaceState({}, "", routeUrl(route));
    return route;
  } catch {
    return { kind: "tenants", page: 1 };
  }
}

function routeUrl(route: AdminRoute) {
  const query = new URLSearchParams();
  if (route.kind !== "services" && route.kind !== "call-details" && route.page !== 1) {
    query.set("page", String(route.page));
  }
  if (route.kind === "calls" && route.definitionId) {
    query.set("definition_id", route.definitionId);
  }
  const suffix = query.size > 0 ? `?${query.toString()}` : "";

  if (route.kind === "tenants") return `/admin${suffix}`;
  const tenant = encodeURIComponent(route.tenantKey);
  if (route.kind === "call-details") {
    return `/admin/tenants/${tenant}/calls/${encodeURIComponent(route.callId)}`;
  }
  return `/admin/tenants/${tenant}/${route.kind}${suffix}`;
}

function readPage() {
  const raw = new URLSearchParams(window.location.search).get("page");
  if (raw === null) return 1;
  const page = Number(raw);
  return Number.isSafeInteger(page) && page > 0 ? page : 1;
}

function readDefinitionFilter() {
  const definitionId = new URLSearchParams(window.location.search).get("definition_id");
  return definitionId && definitionId.length <= 256 ? definitionId : null;
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
