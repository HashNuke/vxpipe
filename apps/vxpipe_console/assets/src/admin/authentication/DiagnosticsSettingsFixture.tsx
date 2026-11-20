import { useMemo, useRef } from "react";
import { DiagnosticsSettingsControl, type DiagnosticsSettingsApi } from "./DiagnosticsSettingsControl";
import { AuthenticationError, type DiagnosticsSettings } from "./authenticationApi";

/** Story-only state: does not contact the API or enable runtime capture. */
export type DiagnosticsScenario = "conflict";
export function DiagnosticsSettingsFixture({ behavior, state, scenario }: { behavior?: string; state?: string; scenario?: DiagnosticsScenario }) {
  const saved = useRef<DiagnosticsSettings>({ enabled: false, revision: 0 });
  const conflictPending = useRef(scenario === "conflict");
  const api = useMemo<DiagnosticsSettingsApi>(() => {
    return {
      async diagnosticsSettings() {
        if (state === "loading") return new Promise<DiagnosticsSettings>(() => {});
        if (state === "unavailable") throw new Error("Unavailable fixture");
        return saved.current;
      },
      async updateDiagnosticsSettings(enabled, revision) {
        if (behavior === "pending") return new Promise<DiagnosticsSettings>(() => {});
        if (behavior === "failure") throw new Error("Save failure fixture");
        if (conflictPending.current) {
          conflictPending.current = false;
          saved.current = { enabled: true, revision: saved.current.revision + 1 };
          throw new AuthenticationError("Conflict", 409, "conflict");
        }
        if (revision !== saved.current.revision) throw new AuthenticationError("Conflict", 409, "conflict");
        saved.current = { enabled, revision: revision + 1 };
        return saved.current;
      },
    };
  }, [behavior, state, scenario]);
  return <DiagnosticsSettingsControl api={api} />;
}
