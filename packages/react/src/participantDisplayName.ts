import type { Participant } from "@vxpipe/core";

/** Role label used outside direct transcript attribution. */
export function participantDisplayName(participant: Participant) {
  return participant.role === "caller" ? "Caller" : participant.name;
}
