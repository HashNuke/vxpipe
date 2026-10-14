import { useState, type ComponentProps } from "react";
import { OnboardingStory } from "../OnboardingStory";
import { NavigationJourney } from "../navigation/NavigationJourney";
import type { SetupTenant } from "../setupCatalog";
import { StoryWorkspace } from "./StoryWorkspace";
export function SetupStory(props: Omit<ComponentProps<typeof OnboardingStory>, "renderFrame">) {
  const [dashboardTenant, setDashboardTenant] = useState<SetupTenant>();
  if (dashboardTenant) return <NavigationJourney theme={props.theme} initialPath={`/t/${dashboardTenant.key}/dashboard`} initialTenants={[{ ...dashboardTenant, id: dashboardTenant.key }]} />;
  return <OnboardingStory {...props} onTenantDashboard={setDashboardTenant} renderFrame={(content, page, tenant, navigate, keys) => <StoryWorkspace theme={props.theme}
    path={page === "platform" ? "/platform/services" : page === "tenants" ? "/tenants" : `/t/${tenant.key}/${page === "keys" ? "api-keys" : page === "samples" ? "samples" : "services"}`}
    initialTenantKeys={{ [tenant.key]: keys }}
    onWorkspaceNavigate={path => {
      if (path === `/t/${tenant.key}/api-keys`) { navigate("keys"); return true; }
      if (path === `/t/${tenant.key}/services`) { navigate("services"); return true; }
      return false;
    }}
    tenant={page === "platform" || page === "tenants" ? undefined : tenant}>{content}</StoryWorkspace>} />;
}
