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

const localTimestampFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: "full",
  timeStyle: "long",
});

export function formatAdminLocalTimestamp(value: string) {
  return localTimestampFormatter.format(new Date(value));
}

const callTimestampFormatter = new Intl.DateTimeFormat("en-US", {
  month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit", hour12: true,
});

export function formatCallTimestamp(value: string) {
  return callTimestampFormatter.format(new Date(value)).replace(/\s([AP]M)$/, (_, period: string) => period.toLowerCase());
}
