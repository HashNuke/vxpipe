import { useMemo, useState } from "react";
import { tenants } from "../authentication/fixtures";
import type { Theme } from "../authentication/types";
import { StoryWorkspace } from "../stories/StoryWorkspace";
import { navigationFixture } from "../navigation/navigationFixtures";
import { apiKeysFixture } from "./apiKeysFixtures";
import { ApiKeysPage } from "./ApiKeysPage";
import type { KeyKind } from "./accessKeysApi";
export function ApiKeysStory({ theme = "dark", scenario = "existing", initialCreating = false, initialKind = "calls", tenantOnly = false, readOnly = false }: {
  theme?: Theme; scenario?: string; initialCreating?: boolean; initialKind?: KeyKind; tenantOnly?: boolean; readOnly?: boolean;
}) {
  const [creating, setCreating] = useState(initialCreating);
  const identity = useMemo(() => {
    const fixture = navigationFixture(tenantOnly || readOnly ? "multiple" : "all");
    if (tenantOnly || readOnly) return { user: fixture.user, role: { ...fixture.role, kind: null,
      grants: [
        { permission: "access_keys.read", scope: "assigned_tenants" as const },
        ...(!readOnly ? ["access_keys.write", "calls.read", "calls.write"].map(permission => ({ permission, scope: "assigned_tenants" as const })) : []),
      ] } };
    return fixture;
  }, [tenantOnly, readOnly]);
  const api = useMemo(() => apiKeysFixture(identity.role, identity.user, tenants, scenario, scenario === "empty" ? [] : undefined), [identity, scenario]);
  return <StoryWorkspace path={creating ? "/api-keys/new" : "/api-keys"} theme={theme} role={identity.role} user={identity.user}
    onWorkspaceNavigate={path => { if (path === "/api-keys") { setCreating(false); return true; } return false; }}>
    <ApiKeysPage key={creating ? "create" : "list"} api={api} initialCreating={creating} initialKind={initialKind} onCreatingChange={setCreating} />
  </StoryWorkspace>;
}
