export function formatCallDuration(durationMs: number | null | undefined): string {
  if (durationMs == null) return "—";
  const seconds = Math.floor(durationMs / 1000);
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return [
    hours ? `${hours}h` : "",
    minutes ? `${minutes}m` : "",
    remainder || !seconds ? `${remainder}s` : "",
  ].filter(Boolean).join(" ");
}
