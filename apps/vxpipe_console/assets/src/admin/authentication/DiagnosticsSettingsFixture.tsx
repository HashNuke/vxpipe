import { useMemo, useRef } from "react";
import { DiagnosticsSettingsControl, type DiagnosticsSettingsApi } from "./DiagnosticsSettingsControl";
import type { DiagnosticsSettings } from "./authenticationApi";

/** Story-only state: does not contact the API or enable runtime capture. */
export function DiagnosticsSettingsFixture({ behavior, state }: { behavior?: string; state?: string }) {
  const saved = useRef<DiagnosticsSettings>({ enabled: false, revision: 0, collection_status: "applied" });
  const api = useMemo<DiagnosticsSettingsApi>(() => {
    return {
      async diagnosticsSettings() {
        if (state === "loading") return new Promise<DiagnosticsSettings>(() => {});
        if (state === "unavailable") throw new Error("Unavailable fixture");
        if (saved.current.collection_status === "applying") saved.current = { ...saved.current, collection_status: "applied" };
        return saved.current;
      },
      async updateDiagnosticsSettings(enabled, revision) {
        if (behavior === "pending") return new Promise<DiagnosticsSettings>(() => {});
        if (behavior === "failure") throw new Error("Save failure fixture");
        saved.current = { enabled, revision: revision + 1, collection_status: "applying" };
        return saved.current;
      },
    };
  }, [behavior, state]);
  return <DiagnosticsSettingsControl api={api} />;
}
