import type { SourceDocument } from "./types";

export const editorFixture: SourceDocument = {
  readOnly: false,
  source: {
    schema_version: "20261004.01",
    name: "New Patient Appointment Intake",
    incoming_call: { caller: "caller", handled_by: "intake" },
    participants: {
      caller: { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } },
      intake: { type: "agent", prompt: "Help the caller schedule an appointment. Transfer to the specialist when needed.", transfers: ["specialist"], tools: { availability: { type: "host", tool: "availability" } }, variable_permissions: { appointment: ["read", "write"] } },
      specialist: { type: "human", description: "Appointment specialist", connection: { service: "web", mode: "receive", admission: "transfer" }, transfer_notice: "Please help this caller with their appointment." },
    },
    call_variables: { sections: { appointment: { schema: { type: "object", properties: { date: { type: "string" } } } } } },
  },
};
