import type { CallDetailsSnapshot } from "@vxpipe/core";

import { parseCallInspectionResponse } from "../callInspection";
import type { CallSpecContext } from "./callTypes";
import type { TenantContext } from "./callSpecTypes";

export type AdminCallDetails = {
  tenant: TenantContext;
  callSpec: Pick<CallSpecContext, "id" | "name">;
  callSpecRevision: number;
  snapshot: CallDetailsSnapshot;
};

export function parseAdminCallDetails(value: unknown): AdminCallDetails {
  if (
    !record(value) ||
    !exactKeys(value, ["tenant", "call_spec", "call_spec_revision", "inspection"]) ||
    !record(value.tenant) ||
    !exactKeys(value.tenant, ["key", "name"]) ||
    typeof value.tenant.key !== "string" ||
    value.tenant.key.length === 0 ||
    typeof value.tenant.name !== "string" ||
    value.tenant.name.length === 0 ||
    !record(value.call_spec) ||
    !exactKeys(value.call_spec, ["id", "name"]) ||
    typeof value.call_spec.id !== "string" ||
    value.call_spec.id.length === 0 ||
    !(value.call_spec.name === null || typeof value.call_spec.name === "string") ||
    !Number.isSafeInteger(value.call_spec_revision) ||
    Number(value.call_spec_revision) <= 0
  ) {
    throw new Error("Invalid admin call details response");
  }

  return {
    tenant: { key: value.tenant.key, name: value.tenant.name },
    callSpec: { id: value.call_spec.id, name: value.call_spec.name },
    callSpecRevision: Number(value.call_spec_revision),
    snapshot: parseCallInspectionResponse(value.inspection),
  };
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exactKeys(value: Record<string, unknown>, expected: string[]) {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return (
    actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index])
  );
}
