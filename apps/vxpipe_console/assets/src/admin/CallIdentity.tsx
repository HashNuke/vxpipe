export function CallIdentity({
  callId,
  definitionRevision,
}: {
  callId: string;
  definitionRevision: number | null;
}) {
  return (
    <span
      className="block truncate font-mono text-xs text-[var(--admin-muted)]"
      title={callId}
    >
      {definitionRevision !== null ? `v${definitionRevision} · ` : null}
      <code>{callId}</code>
    </span>
  );
}
