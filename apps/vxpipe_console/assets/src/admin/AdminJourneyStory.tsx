import {
  callContext,
  callFixture,
  callsForDefinition,
  demoDefinition,
} from "./callFixtures";
import { AdminShell } from "./AdminShell";
import { DefinitionCallsPage } from "./DefinitionCallsPage";
import { definitionFixture, definitions } from "./definitionFixtures";
import { PageNotice } from "./PageNotice";
import { TenantDefinitionsPage } from "./TenantDefinitionsPage";
import { tenantFixture, tenants } from "./tenantFixtures";
import { TenantsPage } from "./TenantsPage";
import { useAdminStoryNavigation } from "./useAdminStoryNavigation";

export function AdminJourneyStory({ theme }: { theme: "dark" | "light" }) {
  const { route, navigate } = useAdminStoryNavigation();

  if (route.page === "calls" || route.page === "call-details") {
    const selectedTenant = tenants.find((tenant) => tenant.key === route.tenantKey) ?? {
      key: route.tenantKey,
      name: route.tenantKey,
    };
    const pendingCallContext =
      route.page === "call-details" ? callContext(route.callId) : null;

    if (route.page === "call-details" && !pendingCallContext) {
      return (
        <AdminShell theme={theme}>
          <main className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6 sm:py-8">
            <PageNotice
              kind="unavailable"
              message="The selected call is not available in this review fixture."
              title="Call unavailable"
            />
          </main>
        </AdminShell>
      );
    }

    const definitionId = route.page === "calls" ? route.definitionId : null;
    const selectedDefinition = definitionId
      ? definitions.find((candidate) => candidate.id === definitionId)
      : null;
    const definition = pendingCallContext?.definition ??
      (selectedDefinition
        ? {
            id: selectedDefinition.id,
            name: selectedDefinition.name,
            latestRevision: selectedDefinition.latestRevision,
            publishedRevision: selectedDefinition.publishedRevision,
          }
        : {
            ...demoDefinition,
            id: definitionId ?? demoDefinition.id,
            name: definitionId ?? demoDefinition.name,
          });
    const fixture = callFixture("populated");
    const state = {
      ...fixture,
      tenant: selectedTenant,
      definition,
      calls:
        pendingCallContext?.calls ?? callsForDefinition(definition.id),
    };

    return (
      <DefinitionCallsPage
        onSelectCall={(callId) =>
          navigate({ page: "call-details", tenantKey: route.tenantKey, callId })
        }
        onSelectTenant={() =>
          navigate({ page: "definitions", tenantKey: route.tenantKey })
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
