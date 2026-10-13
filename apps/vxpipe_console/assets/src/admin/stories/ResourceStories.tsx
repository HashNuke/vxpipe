import { tenantFixture } from "../tenantFixtures";
import { StoryWorkspace } from "./StoryWorkspace";
import { TenantsStory } from "../TenantsStory";
import { TenantCallSpecsStory } from "../TenantCallSpecsStory";
import { CallSpecCallsStory } from "../CallSpecCallsStory";
import { TenantServicesStory } from "../TenantServicesStory";
import { callFixture } from "../callFixtures";
import { callSpecFixture } from "../callSpecFixtures";
import { serviceFixture } from "../serviceFixtures";
import type { ComponentProps } from "react";
export function TenantDirectoryStory(props: ComponentProps<typeof TenantsStory>) {
  const state = tenantFixture(props.scenario);
  const tenants = state.status === "ready" ? state.tenants.map(item => ({ ...item, id: item.key })) : [];
  return <StoryWorkspace path="/tenants" theme={props.theme} tenantOptions={tenants}>{navigate => <TenantsStory {...props} onNavigate={navigate} />}</StoryWorkspace>;
}
export function CallSpecsPageStory(props: ComponentProps<typeof TenantCallSpecsStory>) {
  const tenant = callSpecFixture(props.scenario).tenant;
  return <StoryWorkspace path={`/t/${tenant.key}/call-specs`} tenant={tenant} theme={props.theme}>{navigate => <TenantCallSpecsStory {...props} onNavigate={navigate} />}</StoryWorkspace>;
}
export function CallsPageStory(props: ComponentProps<typeof CallSpecCallsStory>) {
  const tenant = callFixture(props.scenario).tenant;
  return <StoryWorkspace path={`/t/${tenant.key}/calls`} tenant={tenant} theme={props.theme}>{navigate => <CallSpecCallsStory {...props} onNavigate={navigate} />}</StoryWorkspace>;
}
export function ServiceInventoryStory(props: ComponentProps<typeof TenantServicesStory>) {
  const tenant = serviceFixture(props.scenario).tenant;
  return <StoryWorkspace path={`/t/${tenant.key}/services`} tenant={tenant} theme={props.theme}>{navigate => <TenantServicesStory {...props} onNavigate={navigate} />}</StoryWorkspace>;
}
