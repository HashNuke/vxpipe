import type { CallDetailsSnapshot } from "@vxpipe/core";

import { parseCallInspectionResponse } from "../callInspection";
import type { DefinitionContext } from "./callTypes";
import type { TenantContext } from "./definitionTypes";

export type AdminCallDetails = {
  tenant: TenantContext;
  definition: Pick<DefinitionContext, "id" | "name">;
  definitionRevision: number;
  snapshot: CallDetailsSnapshot;
};

export function parseAdminCallDetails(value: unknown): AdminCallDetails {
  if (
    !record(value) ||
    !exactKeys(value, ["tenant", "definition", "definition_revision", "inspection"]) ||
    !record(value.tenant) ||
    !exactKeys(value.tenant, ["key", "name"]) ||
    typeof value.tenant.key !== "string" ||
    value.tenant.key.length === 0 ||
    typeof value.tenant.name !== "string" ||
    value.tenant.name.length === 0 ||
    !record(value.definition) ||
    !exactKeys(value.definition, ["id", "name"]) ||
    typeof value.definition.id !== "string" ||
    value.definition.id.length === 0 ||
    !(value.definition.name === null || typeof value.definition.name === "string") ||
    !Number.isSafeInteger(value.definition_revision) ||
    Number(value.definition_revision) <= 0
  ) {
    throw new Error("Invalid admin call details response");
  }

  return {
    tenant: { key: value.tenant.key, name: value.tenant.name },
    definition: { id: value.definition.id, name: value.definition.name },
    definitionRevision: Number(value.definition_revision),
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
