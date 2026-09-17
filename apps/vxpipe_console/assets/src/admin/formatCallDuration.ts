export function formatCallDuration(
  startedAt: string | null,
  endedAt: string | null,
) {
  if (!startedAt || !endedAt) return null;
  const durationSeconds = Math.max(
    Math.floor((Date.parse(endedAt) - Date.parse(startedAt)) / 1000),
    0,
  );
  const minutes = Math.floor(durationSeconds / 60);
  const seconds = durationSeconds % 60;
  if (minutes === 0) return `${seconds}s`;
  return `${minutes}m ${seconds}s`;
}
