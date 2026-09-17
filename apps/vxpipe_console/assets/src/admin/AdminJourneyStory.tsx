import {
  callContext,
  callFixture,
  callsForDefinition,
  callsForTenant,
} from "./callFixtures";
import { CallDetailsPage } from "./CallDetailsPage";
import { callDetailsFixtureForCall } from "./callDetailsFixtures";
import { DefinitionCallsPage } from "./DefinitionCallsPage";
import { definitionFixture, definitions } from "./definitionFixtures";
import { TenantDefinitionsPage } from "./TenantDefinitionsPage";
import { tenantFixture, tenants } from "./tenantFixtures";
import { TenantsPage } from "./TenantsPage";
import { useAdminStoryNavigation } from "./useAdminStoryNavigation";

export function AdminJourneyStory({ theme }: { theme: "dark" | "light" }) {
  const { route, navigate } = useAdminStoryNavigation();

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
          state={{
            status: "unavailable",
            tenant: selectedTenant,
            definition: null,
            callId: route.callId,
            definitionRevision: null,
            message: "The selected call is not available in this review fixture.",
          }}
          onSelectTenant={() =>
            navigate({ page: "definitions", tenantKey: route.tenantKey })
          }
          onSelectTenants={() => navigate({ page: "tenants" })}
          theme={theme}
        />
      );
    }

    return (
      <CallDetailsPage
        onSelectDefinition={() =>
          navigate({
            page: "calls",
            tenantKey: route.tenantKey,
            definitionId: pendingCallContext.definition.id,
          })
        }
        onSelectTenant={() =>
          navigate({ page: "definitions", tenantKey: route.tenantKey })
        }
        onSelectTenants={() => navigate({ page: "tenants" })}
        state={callDetailsFixtureForCall(
          selectedCall,
          pendingCallContext.definition,
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

    const definitionId = route.definitionId;
    const fixture = callFixture("populated");
    const state = {
      ...fixture,
      tenant: selectedTenant,
      definitions: definitions.map(({ id, name }) => ({ id, name })),
      selectedDefinitionId: definitionId ?? null,
      calls: definitionId ? callsForDefinition(definitionId) : callsForTenant(),
    };

    return (
      <DefinitionCallsPage
        onSelectCall={(callId) =>
          navigate({ page: "call-details", tenantKey: route.tenantKey, callId })
        }
        onSelectTenant={() =>
          navigate({ page: "definitions", tenantKey: route.tenantKey })
        }
        onSelectWorkspace={(destination) =>
          navigate({ page: destination, tenantKey: route.tenantKey })
        }
        onSelectDefinition={(nextDefinitionId) =>
          navigate({
            page: "calls",
            tenantKey: route.tenantKey,
            ...(nextDefinitionId ? { definitionId: nextDefinitionId } : {}),
          })
        }
        onSelectTenants={() => navigate({ page: "tenants" })}
        state={state}
        theme={theme}
      />
    );
  }

  if (route.page === "definitions") {
    const selectedTenant = tenants.find((tenant) => tenant.key === route.tenantKey) ?? {
      key: route.tenantKey,
      name: route.tenantKey,
    };
    const fixture = definitionFixture("populated");
    const state = { ...fixture, tenant: selectedTenant };

    return (
      <TenantDefinitionsPage
        onSelectDefinition={(definitionId) =>
          navigate({
            page: "calls",
            tenantKey: route.tenantKey,
            definitionId,
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
        navigate({ page: "definitions", tenantKey })
      }
      state={tenantFixture("populated")}
      theme={theme}
    />
  );
}
