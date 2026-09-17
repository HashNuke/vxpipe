import { useState } from "react";

import {
  applyCredentialCreation,
  serviceFixture,
  type ServiceFixtureScenario,
} from "./serviceFixtures";
import { TenantServicesPage } from "./TenantServicesPage";

export function TenantServicesStory({
  scenario,
  theme,
}: {
  scenario: ServiceFixtureScenario;
  theme: "dark" | "light";
}) {
  const [state, setState] = useState(() => serviceFixture(scenario));

  return (
    <TenantServicesPage
      onCreateCredential={(draft) => {
        setState((current) => applyCredentialCreation(current, draft));
      }}
      onSelectTenant={() =>
        window.history.pushState(
          {},
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/definitions`,
        )
      }
      onSelectTenants={() => window.history.pushState({}, "", "#/admin")}
      onSelectWorkspace={(destination) =>
        window.history.pushState(
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
