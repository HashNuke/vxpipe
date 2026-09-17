const timestampFormatter = new Intl.DateTimeFormat(undefined, {
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
  month: "short",
  year: "numeric",
});

export function formatAdminTimestamp(value: string) {
  return timestampFormatter.format(new Date(value));
}
