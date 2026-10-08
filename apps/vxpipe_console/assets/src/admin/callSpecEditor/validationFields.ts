import type { SourceIssue } from "./types";
export type ObjectValue = Record<string, unknown>;
export const record = (value: unknown): value is ObjectValue => typeof value === "object" && value !== null && !Array.isArray(value);

/** Collects fixed, value-free messages while leaving the portable source untouched. */
export class Fields {
  readonly issues: SourceIssue[] = [];
  issue(path: string[], reason: string): void {
    if (!this.issues.some((issue) => issue.path.length === path.length && issue.path.every((part, index) => part === path[index]))) {
      this.issues.push({ code: "invalid_call_spec", path, reason });
    }
  }
  object(value: unknown, path: string[], allowed?: readonly string[]): ObjectValue {
    if (!record(value)) { this.issue(path, value === undefined ? "is required" : "must be an object"); return {}; }
    if (allowed) for (const key of Object.keys(value)) if (!allowed.includes(key)) this.issue([...path, key], "is not supported");
    return value;
  }
  text(value: unknown, path: string[], maximum: number, optional = false): void {
    if (optional && (value === null || value === undefined)) return;
    if (value === undefined) this.issue(path, "is required");
    else if (typeof value !== "string" || !value.trim() || new TextEncoder().encode(value).length > maximum) this.issue(path, `must be a non-empty string of at most ${maximum} bytes`);
  }
  identifier(value: unknown, path: string[]): value is string {
    const valid = typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
    if (!valid) this.issue(path, value === undefined ? "is required" : "must contain 1–128 URL-safe identifier characters");
    return valid;
  }
  enumeration(value: unknown, path: string[], values: readonly string[]): void {
    if (typeof value !== "string" || !values.includes(value)) this.issue(path, value === undefined ? "is required" : "must be a supported value");
  }
  integer(value: unknown, path: string[], minimum: number, maximum: number): void {
    if (typeof value !== "number" || !Number.isSafeInteger(value) || value < minimum || value > maximum) this.issue(path, `must be between ${minimum} and ${maximum}`);
  }
  phone(value: unknown, path: string[]): void {
    if (typeof value !== "string" || !/^\+[1-9][0-9]{1,14}$/.test(value)) this.issue(path, "must be an E.164 telephone number");
  }
}
