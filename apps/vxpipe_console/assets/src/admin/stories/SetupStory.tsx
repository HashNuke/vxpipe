import type { ComponentProps } from "react";
import { OnboardingStory } from "../OnboardingStory";
import { StoryWorkspace } from "./StoryWorkspace";
export function SetupStory(props: Omit<ComponentProps<typeof OnboardingStory>, "renderFrame">) {
  return <OnboardingStory {...props} renderFrame={(content, page, tenant, navigate, keys) => <StoryWorkspace theme={props.theme}
    path={page === "platform" ? "/platform/services" : page === "tenants" ? "/tenants" : `/t/${tenant.key}/${page === "keys" ? "api-keys" : page === "samples" ? "samples" : "services"}`}
    initialTenantKeys={{ [tenant.key]: keys }}
    onWorkspaceNavigate={path => {
      if (path === `/t/${tenant.key}/api-keys`) { navigate("keys"); return true; }
      if (path === `/t/${tenant.key}/services`) { navigate("services"); return true; }
      return false;
    }}
    tenant={page === "platform" || page === "tenants" ? undefined : tenant}>{content}</StoryWorkspace>} />;
}
