import {
  callContext,
  callFixture,
  callsForCallSpec,
  callsForTenant,
} from "./callFixtures";
import { CallDetailsPage } from "./CallDetailsPage";
import { callDetailsFixtureForCall } from "./callDetailsFixtures";
import { adminStoryHref, callDetailsStoryHref } from "./adminStoryHref";
import { CallSpecCallsPage } from "./CallSpecCallsPage";
import { callSpecFixture, callSpecs } from "./callSpecFixtures";
import { TenantCallSpecsPage } from "./TenantCallSpecsPage";
import { applyCredentialCreation, serviceFixture } from "./serviceFixtures";
import { TenantServicesPage } from "./TenantServicesPage";
import type { AdminStoryRoute } from "./adminStoryRoute";
import type { TenantContext } from "./callSpecTypes";
import { tenantFixture, tenants } from "./tenantFixtures";
import { TenantsPage } from "./TenantsPage";
import { useAdminStoryNavigation } from "./useAdminStoryNavigation";

function JourneyServicesPage({
  tenant,
  theme,
  navigate,
}: {
  tenant: TenantContext;
  theme: "dark" | "light";
  navigate: (route: AdminStoryRoute) => void;
}) {
  const [state, setState] = useState(() => ({
    ...serviceFixture("populated"),
    tenant,
  }));

  return (
    <TenantServicesPage
      onCreateCredential={(draft) =>
        setState((current) => applyCredentialCreation(current, draft))
      }
      onTestCredential={async () => ({ status: "valid" })}
      onSelectTenant={() => navigate({ page: "call-specs", tenantKey: tenant.key })}
      onSelectTenants={() => navigate({ page: "tenants" })}
      onSelectWorkspace={(destination) =>
        navigate({ page: destination, tenantKey: tenant.key })
      }
      state={state}
      theme={theme}
    />
  );
}

export function AdminJourneyStory({ theme }: { theme: "dark" | "light" }) {
  const { route, navigate } = useAdminStoryNavigation();

  if (route.page === "services") {
    const selectedTenant = tenants.find((tenant) => tenant.key === route.tenantKey) ?? {
      key: route.tenantKey,
      name: route.tenantKey,
    };
    return <JourneyServicesPage key={selectedTenant.key} navigate={navigate} tenant={selectedTenant} theme={theme} />;
  }

  if (route.page === "call-details") {
    const selectedTenant = tenants.find((tenant) => tenant.key === route.tenantKey) ?? {
      key: route.tenantKey,
      name: route.tenantKey,
    };
    const pendingCallContext = callContext(route.callId);
    const selectedCall = pendingCallContext?.calls.find(
      (call) => call.id === route.callId,
    );
    if (!pendingCallContext || !selectedCall) {
      return (
        <CallDetailsPage
          contextHref={(path) => adminStoryHref(path, theme)}
          state={{
            status: "unavailable",
            tenant: selectedTenant,
            callSpec: null,
            callId: route.callId,
            callSpecRevision: null,
            message: "The selected call is not available in this review fixture.",
          }}
          theme={theme}
        />
      );
    }

    return (
      <CallDetailsPage
        contextHref={(path) => adminStoryHref(path, theme)}
        state={callDetailsFixtureForCall(
          selectedCall,
          pendingCallContext.callSpec,
          selectedTenant,
        )}
        theme={theme}
      />
    );
  }

  if (route.page === "calls") {
    const selectedTenant = tenants.find((tenant) => tenant.key === route.tenantKey) ?? {
      key: route.tenantKey,
      name: route.tenantKey,
    };

    const callSpecId = route.callSpecId;
    const fixture = callFixture("populated");
    const state = {
      ...fixture,
      tenant: selectedTenant,
      callSpecs: callSpecs.map(({ id, name }) => ({ id, name })),
      selectedCallSpecId: callSpecId ?? null,
      calls: callSpecId ? callsForCallSpec(callSpecId) : callsForTenant(),
    };

    return (
      <CallSpecCallsPage
        callHref={(callId) => callDetailsStoryHref(route.tenantKey, callId, theme)}
        onSelectTenant={() =>
          navigate({ page: "call-specs", tenantKey: route.tenantKey })
        }
        onSelectWorkspace={(destination) =>
          navigate({ page: destination, tenantKey: route.tenantKey })
        }
        onSelectCallSpec={(nextCallSpecId) =>
          navigate({
            page: "calls",
            tenantKey: route.tenantKey,
            ...(nextCallSpecId ? { callSpecId: nextCallSpecId } : {}),
          })
        }
        onSelectTenants={() => navigate({ page: "tenants" })}
        state={state}
        theme={theme}
      />
    );
  }

  if (route.page === "call-specs") {
    const selectedTenant = tenants.find((tenant) => tenant.key === route.tenantKey) ?? {
      key: route.tenantKey,
      name: route.tenantKey,
    };
    const fixture = callSpecFixture("populated");
    const state = { ...fixture, tenant: selectedTenant };

    return (
      <TenantCallSpecsPage
        onSelectCallSpec={(callSpecId) =>
          navigate({
            page: "calls",
            tenantKey: route.tenantKey,
            callSpecId,
          })
        }
        onSelectWorkspace={(destination) =>
          navigate({ page: destination, tenantKey: route.tenantKey })
        }
        onSelectTenants={() => navigate({ page: "tenants" })}
        state={state}
        theme={theme}
      />
    );
  }

  return (
    <TenantsPage
      onSelectTenant={(tenantKey) =>
        navigate({ page: "call-specs", tenantKey })
      }
      state={tenantFixture("populated")}
      theme={theme}
    />
  );
}
import { useState } from "react";
