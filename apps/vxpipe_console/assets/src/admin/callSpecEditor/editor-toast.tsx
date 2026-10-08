import { PageToast } from "../PageToast";
import type { ActionFeedback } from "./errorPresentation";
const labels = { show: "Show", retry: "Retry", services: "Open services", reload: "Reload" };
export function EditorToast({ feedback, onAction, onDismiss, busy = false }: { feedback: ActionFeedback | null; onAction: (action: NonNullable<ActionFeedback["action"]>) => void; onDismiss: () => void; busy?: boolean }) {
  if (!feedback) return null;
  const action = feedback.action;
  return <PageToast kind={feedback.tone} message={feedback.message} onDismiss={onDismiss}
    action={action ? { label: action === "show" && feedback.message.startsWith("Fix ") ? "Show first issue" : labels[action], onClick: () => onAction(action), disabled: busy && action !== "show" } : undefined} />;
}
