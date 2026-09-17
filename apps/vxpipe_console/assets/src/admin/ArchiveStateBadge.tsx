import { classNames } from "./classNames";
import type { CallArchiveState } from "./callTypes";

const labels: Record<CallArchiveState, string> = {
  complete: "Complete",
  incomplete: "Partial",
  unconfirmed: "Unconfirmed",
};

export function ArchiveStateBadge({ state }: { state: CallArchiveState }) {
  return (
    <span
      className={classNames(
        "inline-flex min-h-6 items-center rounded-full border px-2 font-mono text-xs font-bold uppercase tracking-[0.04em]",
        state === "complete" &&
          "border-[var(--admin-green)]/35 bg-[var(--admin-green-soft)] text-[var(--admin-green)]",
        state === "incomplete" &&
          "border-[var(--admin-amber)]/35 bg-[var(--admin-amber-soft)] text-[var(--admin-amber)]",
        state === "unconfirmed" &&
          "border-[var(--admin-line)] bg-[var(--admin-soft)] text-[var(--admin-muted)]",
      )}
    >
      {labels[state]}
    </span>
  );
}
