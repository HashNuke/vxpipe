import { classNames } from "./classNames";
import type { CallLifecycleState } from "./callTypes";

const labels: Record<CallLifecycleState, string> = {
  prepared: "Prepared",
  admitting: "Admitting",
  running: "Ongoing",
  ended: "Ended",
  failed: "Failed",
};

export function CallStateBadge({ state }: { state: CallLifecycleState }) {
  return (
    <span
      className={classNames(
        "inline-flex min-h-6 items-center rounded-full border px-2 font-mono text-xs font-bold uppercase tracking-[0.04em]",
        state === "ended" &&
          "border-[var(--admin-green)]/35 bg-[var(--admin-green-soft)] text-[var(--admin-green)]",
        state === "running" &&
          "border-[var(--admin-blue)]/35 bg-[var(--admin-blue-soft)] text-[var(--admin-blue)]",
        (state === "prepared" || state === "admitting") &&
          "border-[var(--admin-amber)]/35 bg-[var(--admin-amber-soft)] text-[var(--admin-amber)]",
        state === "failed" &&
          "border-[var(--admin-red)]/35 bg-[var(--admin-red-soft)] text-[var(--admin-red)]",
      )}
    >
      {labels[state]}
    </span>
  );
}
