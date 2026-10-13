import type { ComponentProps } from "react";
import { AdminShell } from "../AdminShell";
import { AuthenticationJourney } from "../authentication/AuthenticationJourney";
import { StoryWorkspace } from "./StoryWorkspace";
export function AuthenticationStory(props: Omit<ComponentProps<typeof AuthenticationJourney>, "renderFrame">) {
  return <AuthenticationJourney {...props} renderFrame={(content, path, session) =>
    session.user && session.role && !path.startsWith("/auth/") ? <StoryWorkspace path={path} theme={props.theme} user={session.user} role={session.role} onNavigate={session.navigate} onLogout={session.logout}>{content}</StoryWorkspace>
      : <AdminShell showHeader={false} theme={props.theme}>{content}</AdminShell>} />;
}
