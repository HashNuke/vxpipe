import type { CallConsoleController } from "@vxpipe/core";

import type { DefinitionContext } from "./callTypes";
import type { TenantContext } from "./definitionTypes";

type CallDetailsIdentity = {
  tenant: TenantContext;
  callId: string;
};

type KnownDefinition = {
  definition: DefinitionContext;
  definitionRevision: number;
};

type OptionalDefinition = {
  definition: DefinitionContext | null;
  definitionRevision: number | null;
};

export type CallDetailsPageState = CallDetailsIdentity &
  (
    | (OptionalDefinition & { status: "loading" })
    | (OptionalDefinition & { status: "unavailable"; message: string })
    | (OptionalDefinition & { status: "malformed"; message: string })
    | (KnownDefinition & {
        status: "ready";
        controller: CallConsoleController;
        completeness: "complete" | "incomplete" | "unconfirmed";
      })
  );
