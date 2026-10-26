import { StoryWorkspace } from "../stories/StoryWorkspace";
import { ServiceConnectionsPreview } from "./ServiceConnectionsPreview";
import type { Scenario } from "./fixtures";

export function McpServicesStory({ scenario = "services", theme = "dark", canManagePlatform = true }: {
  scenario?: Scenario;
  theme?: "dark" | "light";
  canManagePlatform?: boolean;
}) {
  const tenant = { key: "demo_mcp_preview", name: "Demo" };
  return <StoryWorkspace path={`/t/${tenant.key}/services`} tenant={tenant} theme={theme}>
    <ServiceConnectionsPreview scenario={scenario} tenant={tenant} canManagePlatform={canManagePlatform} />
  </StoryWorkspace>;
}
