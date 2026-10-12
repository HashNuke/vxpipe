import { parseSourceJson, stringifySourceJson } from "./source-json";
import type { JsonValue, VariableSchema, VariableType } from "./types";

export function variableType(schema: VariableSchema): VariableType | undefined {
  return Array.isArray(schema.type) ? schema.type.find(type => type !== "null") ?? "null" : schema.type;
}
function matches(value: JsonValue, type: VariableType | undefined): boolean {
  switch (type) {
    case "integer": return typeof value === "bigint" || (typeof value === "number" && Number.isInteger(value));
    case "number": return typeof value === "bigint" || (typeof value === "number" && Number.isFinite(value));
    case "object": return typeof value === "object" && value !== null && !Array.isArray(value);
    case "array": return Array.isArray(value);
    case "null": return value === null;
    case undefined: return true;
    default: return typeof value === type;
  }
}
export function parseEnumValue(text: string, type: VariableType | undefined): JsonValue {
  if (!text.trim()) throw new Error("Enter a value first.");
  let value: JsonValue;
  try { value = type === "string" ? text.trim() : parseSourceJson(text) as JsonValue; }
  catch { throw new Error(`Enter a valid ${type ?? "JSON"} value.`); }
  if (!matches(value, type)) throw new Error(`Enter a valid ${type ?? "JSON"} value.`);
  return value;
}
export function enumValueKey(value: JsonValue): string {
  if (Array.isArray(value)) return `[${value.map(enumValueKey).join(",")}]`;
  if (value !== null && typeof value === "object") return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${enumValueKey(value[key]!)}`).join(",")}}`;
  return stringifySourceJson(value)!;
}
export function enumValueLabel(value: JsonValue): string {
  return typeof value === "string" && value.length ? value : stringifySourceJson(value)!;
}
export function validateVariableEnums(schema: VariableSchema): string | undefined {
  if (schema.enum) {
    if (!schema.enum.length) return "Add at least one valid value, or uncheck Enum?.";
    if (schema.enum.some(value => value !== null && !matches(value, variableType(schema)))) return "Valid values must match the selected field type.";
  }
  for (const child of Object.values(schema.properties ?? {})) {
    const error = validateVariableEnums(child);
    if (error) return error;
  }
  return schema.items ? validateVariableEnums(schema.items) : undefined;
}
