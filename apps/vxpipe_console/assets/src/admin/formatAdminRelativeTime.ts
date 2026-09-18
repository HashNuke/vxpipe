const units = [
  ["year", 365 * 24 * 60 * 60],
  ["month", 30 * 24 * 60 * 60],
  ["day", 24 * 60 * 60],
  ["hour", 60 * 60],
  ["minute", 60],
] as const;

function pluralize(value: number, unit: string) {
  return `${value} ${unit}${value === 1 ? "" : "s"}`;
}

export function formatAdminRelativeTime(value: string, now = new Date()) {
  const difference = Math.round((now.getTime() - new Date(value).getTime()) / 1_000);
  const absoluteDifference = Math.abs(difference);

  if (absoluteDifference < 60) return "just now";

  const unit = units.find(([, seconds]) => absoluteDifference >= seconds);
  if (!unit) return "just now";

  const [name, seconds] = unit;
  const quantity = Math.floor(absoluteDifference / seconds);
  return difference >= 0
    ? `${pluralize(quantity, name)} ago`
    : `in ${pluralize(quantity, name)}`;
}
