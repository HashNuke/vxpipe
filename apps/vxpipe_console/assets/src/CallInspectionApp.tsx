import { useEffect, useState } from "react";
import {
  createCallDetailsController,
  createCallDetailsStore,
  type CallConsoleController,
  type CallDetailsController,
  type CallDetailsLoader,
} from "@vxpipe/core";
import { CallConsole } from "@vxpipe/react";

import { createCallInspectionLoader } from "./callInspection";

type LoadState =
  | { state: "loading" }
  | { state: "ready"; controller: CallConsoleController }
  | { state: "error"; message: string };

export function CallInspectionApp({
  callId,
  loader,
}: {
  callId: string;
  loader?: CallDetailsLoader;
}) {
  const [loadState, setLoadState] = useState<LoadState>({ state: "loading" });

  useEffect(() => {
    const source = loader ?? createCallInspectionLoader(callId);
    const abort = new AbortController();
    let history: CallDetailsController | undefined;
    setLoadState({ state: "loading" });

    void source.refresh(abort.signal).then(
      (snapshot) => {
        if (abort.signal.aborted) return;
        const store = createCallDetailsStore(snapshot);
        history = createCallDetailsController({ store, loader: source });
        setLoadState({
          state: "ready",
          controller: { details: history, history },
        });
      },
      (error: unknown) => {
        if (abort.signal.aborted) return;
        setLoadState({
          state: "error",
          message:
            error instanceof Error
              ? error.message
              : "Call inspection is unavailable.",
        });
      },
    );

    return () => {
      abort.abort();
      history?.dispose();
    };
  }, [callId, loader]);

  if (loadState.state === "loading") {
    return (
      <main className="vx-inspection-state" aria-busy="true">
        Loading call…
      </main>
    );
  }

  if (loadState.state === "error") {
    return (
      <main className="vx-inspection-state vx-inspection-error" role="alert">
        {loadState.message}
      </main>
    );
  }

  return <CallConsole controller={loadState.controller} theme="dark" maxHeight="calc(100dvh - 32px)" />;
}
