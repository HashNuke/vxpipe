import { parse, stringify } from "lossless-json";

/** Large JSON integers use bigint internally; the wire format remains JSON numbers. */
export function parseSourceNumber(text: string): number | bigint {
  const number = Number(text);
  return /^-?\d+$/.test(text) && !Number.isSafeInteger(number) ? BigInt(text) : number;
}

export function parseSourceJson(text: string): unknown {
  return parse(text, undefined, { parseNumber: parseSourceNumber });
}

export function stringifySourceJson(value: unknown, space?: number): string | undefined {
  return stringify(value, undefined, space);
}
