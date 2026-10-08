import { CircleCheck, CircleX, X } from "lucide-react";
import { Button } from "./components/ui/button";
import { useEffect } from "react";

export function PageToast({
  message,
  kind = "success",
  onDismiss,
  action,
}: {
  message: string;
  kind?: "success" | "error";
  onDismiss: () => void;
  action?: { label: string; onClick: () => void; disabled?: boolean };
}) {
  useEffect(() => {
    if (kind === "error") return;
    const timer = window.setTimeout(onDismiss, 6000);
    return () => window.clearTimeout(timer);
  }, [kind, message, onDismiss]);

  return (
    <div
      aria-label="Notification"
      className="fixed bottom-4 right-4 z-[60] flex max-w-[min(24rem,calc(100vw-2rem))] items-start gap-3 rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] px-4 py-3 text-sm text-[var(--admin-ink)] shadow-lg sm:bottom-6 sm:right-6"
      role={kind === "error" ? "alert" : "status"}
    >
      {kind === "error" ? (
        <CircleX aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-[var(--admin-red)]" />
      ) : (
        <CircleCheck aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-[var(--admin-green)]" />
      )}
      <div className="min-w-0 flex-1 space-y-2"><p className="wrap-anywhere">{message}</p>{action && <Button variant="outline" size="sm" onClick={action.onClick} disabled={action.disabled}>{action.label}</Button>}</div>
      <button
        aria-label="Dismiss notification"
        className="-mr-1 -mt-1 inline-flex size-7 shrink-0 items-center justify-center rounded-sm text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)] focus-visible:outline-2"
        onClick={onDismiss}
        type="button"
      >
        <X aria-hidden="true" className="size-4" />
      </button>
    </div>
  );
}
