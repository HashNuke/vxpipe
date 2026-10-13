import type { ComponentProps } from "react";
import { OnboardingStory } from "../OnboardingStory";
import { StoryWorkspace } from "./StoryWorkspace";
export function SetupStory(props: Omit<ComponentProps<typeof OnboardingStory>, "renderFrame">) {
  return <OnboardingStory {...props} renderFrame={(content, page, tenant) => <StoryWorkspace theme={props.theme}
    path={page === "platform" ? "/platform/services" : page === "tenants" ? "/tenants" : `/t/${tenant.key}/services`}
    tenant={page === "platform" || page === "tenants" ? undefined : tenant}>{content}</StoryWorkspace>} />;
}
