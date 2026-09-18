import type { CallConsoleController } from "@vxpipe/core";

import type { CallSpecContext } from "./callTypes";
import type { TenantContext } from "./callSpecTypes";

type CallDetailsIdentity = {
  tenant: TenantContext;
  callId: string;
};

type KnownCallSpec = {
  callSpec: Pick<CallSpecContext, "id" | "name">;
  callSpecRevision: number;
};

type OptionalCallSpec = {
  callSpec: Pick<CallSpecContext, "id" | "name"> | null;
  callSpecRevision: number | null;
};

export type CallDetailsPageState = CallDetailsIdentity &
  (
    | (OptionalCallSpec & { status: "loading" })
    | (OptionalCallSpec & { status: "unavailable"; message: string })
    | (OptionalCallSpec & { status: "malformed"; message: string })
    | (KnownCallSpec & {
        status: "ready";
        controller: CallConsoleController;
        completeness: "complete" | "incomplete" | "unconfirmed";
      })
  );
