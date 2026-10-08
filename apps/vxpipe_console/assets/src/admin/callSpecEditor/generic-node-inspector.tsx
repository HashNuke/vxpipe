import { InspectorShell } from "./inspector-primitives";

/** The copied generic inspector covers stale selections; all supported kinds have editors. */
export function GenericNodeInspector({ participantKey }: { participantKey: string }) {
  return <InspectorShell title={participantKey} subtitle="Participant unavailable">
    <p className="text-sm text-muted-foreground">This participant is no longer in the call spec. Select another participant or Call settings.</p>
  </InspectorShell>;
}
