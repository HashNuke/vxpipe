import { AlertTriangle, Database } from "lucide-react";

export function PageNotice({
  kind,
  title,
  message,
}: {
  kind: "empty" | "unavailable";
  title: string;
  message: string;
}) {
  const Icon = kind === "empty" ? Database : AlertTriangle;
  return (
    <section
      aria-live="polite"
      className="flex min-h-56 flex-col items-center justify-center border border-[var(--admin-line)] bg-[var(--admin-panel)] px-6 py-10 text-center"
      role={kind === "unavailable" ? "alert" : "status"}
    >
      <Icon
        aria-hidden="true"
        className={
          kind === "unavailable"
            ? "mb-4 size-5 text-[var(--admin-red)]"
            : "mb-4 size-5 text-[var(--admin-muted)]"
        }
      />
      <h2 className="text-sm font-semibold">{title}</h2>
      <p className="mt-2 max-w-[48ch] text-sm text-[var(--admin-muted)]">
        {message}
      </p>
    </section>
  );
}
