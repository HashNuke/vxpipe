import type { JsonValue } from "@vxpipe/core";

export type ObjectValue = Record<string, unknown>;

export class CallInspectionResponseError extends Error {
  readonly status: number | null;

  constructor(message: string, status: number | null = null) {
    super(message);
    this.name = "CallInspectionResponseError";
    this.status = status;
  }
}

export function object(value: unknown, path: string): ObjectValue {
  if (typeof value !== "object" || value === null || Array.isArray(value)) invalid(path);
  return value as ObjectValue;
}

export function array(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) invalid(path);
  return value;
}

export function string(value: unknown, path: string): string {
  if (typeof value !== "string") invalid(path);
  return value;
}

export function nullableString(value: unknown, path: string): string | null {
  return value === null ? null : string(value, path);
}

export function optionalString(value: unknown, path: string): string | undefined {
  return value === undefined ? undefined : string(value, path);
}

export function instant(value: unknown, path: string): string {
  const result = string(value, path);
  if (!Number.isFinite(Date.parse(result))) invalid(path);
  return result;
}

export function nullableInstant(value: unknown, path: string): string | null {
  return value === null ? null : instant(value, path);
}

export function revision(value: unknown, path: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) invalid(path);
  return value as number;
}

export function nullableNumber(value: unknown, path: string): number | null {
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) invalid(path);
  return value;
}

export function nullableNonnegativeNumber(value: unknown, path: string): number | null {
  const result = nullableNumber(value, path);
  if (result !== null && result < 0) invalid(path);
  return result;
}

export function optionalInteger(value: unknown, path: string): number | undefined {
  if (value === undefined) return undefined;
  if (!Number.isInteger(value)) invalid(path);
  return value as number;
}

export function literal(value: unknown, expected: unknown, path: string): void {
  if (value !== expected) invalid(path);
}

export function member<const T extends readonly string[]>(
  value: unknown,
  values: T,
  path: string,
): T[number] {
  if (typeof value !== "string" || !values.includes(value)) invalid(path);
  return value as T[number];
}

export function optionalJson(value: unknown, path: string): JsonValue | undefined {
  return value === undefined ? undefined : json(value, path);
}

export function json(value: unknown, path: string): JsonValue {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean" ||
    (typeof value === "number" && Number.isFinite(value))
  ) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((entry, index) => json(entry, `${path}[${index}]`));
  }
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, json(entry, `${path}.${key}`)]),
    );
  }
  return invalid(path);
}

export function invalid(path: string): never {
  throw new CallInspectionResponseError(`Invalid call inspection field: ${path}.`);
}
