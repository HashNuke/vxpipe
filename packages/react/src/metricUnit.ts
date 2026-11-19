/** Display aliases only; persisted observations keep their original units. */
export function metricUnit(unit: string): string {
  switch (unit) {
    case "milliseconds": return "ms";
    case "characters": return "ch";
    case "requests": return "reqs";
    default: return unit;
  }
}
