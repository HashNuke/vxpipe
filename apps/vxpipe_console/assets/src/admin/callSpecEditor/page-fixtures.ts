import { modelCatalogFixture } from "../modelCatalogFixtures";
import { editorFixture } from "./editorFixtures";
import type { EditorSnapshot } from "./editor-state";
import { newCallSpec } from "./seed";
import { parseSource } from "./source";

export type EditorScenario = "default" | "new" | "invalid" | "published" | "outgoing" | "historical" | "long" | "large-integers";
export function pageSnapshot(scenario: EditorScenario): EditorSnapshot {
  if (scenario === "new") return { document: newCallSpec(modelCatalogFixture) };
  const document = structuredClone(editorFixture);
  document.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" } } };
  const intake = document.source.participants.intake;
  if (scenario === "invalid" && intake?.type === "agent") { intake.prompt = ""; document.source.limits = { max_duration_ms: -1 }; }
  if (scenario === "outgoing") {
    delete document.source.incoming_call;
    document.source.outgoing_call = { callee: "caller", handled_by: "intake", ring_timeout_ms: 30000 };
    document.source.participants.caller = { type: "human", connection: { service: "office-phone", mode: "dial", number: "+14155550123" } };
  }
  if (scenario === "long" && intake?.type === "agent") {
    document.source.name = "New patient appointment intake, appointment changes, follow-up questions and specialist transfer for the regional care team";
    intake.prompt = "Ask one question at a time. Confirm the appointment date with the caller before booking.\n".repeat(120);
    intake.description = "Handles appointment scheduling and routes complex questions to the appropriate specialist. ".repeat(8);
  }
  if (scenario === "large-integers") {
    document.source.call_variables!.sections!.account = { schema: { type: "object", properties: {
      id: { type: "integer", enum: [9007199254740992n, 9007199254740993n], minimum: -9007199254740993n },
    } } };
  }
  if (scenario === "historical") {
    document.source.schema_version = "20260915.01";
    document.source.entry_caller = "caller"; document.source.entry_receiver = "intake";
    delete document.source.incoming_call;
    return { document: parseSource(JSON.stringify(document.source)), saved: { callSpecId: "appointments", revision: 1, publishedRevision: 1 } };
  }
  return { document, saved: { callSpecId: "appointments", revision: 3, publishedRevision: scenario === "published" ? 3 : null } };
}
