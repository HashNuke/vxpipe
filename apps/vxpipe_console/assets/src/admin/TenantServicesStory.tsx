import { useState } from "react";

import {
  applyCredentialCreation,
  serviceFixture,
  type ServiceFixtureScenario,
} from "./serviceFixtures";
import { TenantServicesPage } from "./TenantServicesPage";

export function TenantServicesStory({
  scenario,
  onNavigate,
  theme,
}: {
  onNavigate?: (path: string) => void;
  scenario: ServiceFixtureScenario;
  theme: "dark" | "light";
}) {
  const [state, setState] = useState(() => serviceFixture(scenario));

  return (
    <TenantServicesPage
      onCreateCredential={(draft) => {
        setState((current) => applyCredentialCreation(current, draft));
      }}
      onTestCredential={async () => ({ status: "valid" })}
      onSelectTenant={() =>
        onNavigate ? onNavigate(`/t/${state.tenant.key}/dashboard`) : window.history.pushState(
          {},
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/call-specs`,
        )
      }
      onSelectTenants={() => onNavigate ? onNavigate("/tenants") : window.history.pushState({}, "", "#/admin")}
      onSelectWorkspace={(destination) =>
        onNavigate ? onNavigate(`/t/${state.tenant.key}/${destination}`) : window.history.pushState(
          { destination },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/${destination}`,
        )
      }
      state={state}
      theme={theme}
    />
  );
}
