import { definitionFixture } from "./definitionFixtures";
import { TenantDefinitionsPage } from "./TenantDefinitionsPage";
import { tenantFixture, tenants } from "./tenantFixtures";
import { TenantsPage } from "./TenantsPage";
import { useAdminStoryNavigation } from "./useAdminStoryNavigation";

export function AdminJourneyStory({ theme }: { theme: "dark" | "light" }) {
  const { route, navigate } = useAdminStoryNavigation();

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
            page: "definitions",
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
