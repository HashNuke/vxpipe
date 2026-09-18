export function CallIdentity({
  callId,
  callSpecRevision,
}: {
  callId: string;
  callSpecRevision: number | null;
}) {
  return (
    <span
      className="block truncate font-mono text-xs text-[var(--admin-muted)]"
      title={callId}
    >
      {callSpecRevision !== null ? `v${callSpecRevision} · ` : null}
      <code>{callId}</code>
    </span>
  );
}
