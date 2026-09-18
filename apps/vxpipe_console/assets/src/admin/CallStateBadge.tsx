import { classNames } from "./classNames";
import type { CallDirectoryState } from "./callTypes";

const labels: Record<CallDirectoryState, string> = {
  ongoing: "Ongoing",
  ended: "Ended",
};

export function CallStateBadge({ state }: { state: CallDirectoryState }) {
  return (
    <span
      className={classNames(
        "inline-flex min-h-6 items-center rounded-full border px-2 font-mono text-xs font-bold uppercase tracking-[0.04em]",
        state === "ended" &&
          "border-[var(--admin-green)]/35 bg-[var(--admin-green-soft)] text-[var(--admin-green)]",
        state === "ongoing" &&
          "border-[var(--admin-blue)]/35 bg-[var(--admin-blue-soft)] text-[var(--admin-blue)]",
      )}
    >
      {labels[state]}
    </span>
  );
}
