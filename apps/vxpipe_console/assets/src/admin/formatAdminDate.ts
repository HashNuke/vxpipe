const dateFormatter = new Intl.DateTimeFormat(undefined, {
  day: "numeric",
  month: "short",
  year: "numeric",
});

export function formatAdminDate(value: string) {
  return dateFormatter.format(new Date(value));
}
