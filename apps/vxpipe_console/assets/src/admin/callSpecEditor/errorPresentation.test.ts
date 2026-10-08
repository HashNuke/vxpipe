import { expect, test } from "vitest";
import fixture from "../../../../../../examples/contracts/call-spec-editor-validation.json";
import { locateIssue, actionOutcome } from "./errorPresentation";
import type { CallSpecSource } from "./types";
const source = fixture.bases.incoming as CallSpecSource;

const locations = [
  [["participants", "assistant", "prompt"], "assistant", "prompt", "Agent assistant › Prompt"],
  [["participants", "assistant", "first_message", "text"], "assistant", "prompt", "Agent assistant › First message"],
  [["participants", "assistant", "capabilities", "text_to_speech", "model"], "assistant", "voice", "Agent assistant › Text to speech"],
  [["participants", "assistant", "variable_permissions", "contact"], "assistant", "variables", "Agent assistant › Section permissions"],
  [["participants", "assistant", "transfers", "0"], "assistant", "transfers", "Agent assistant › Transfer destinations"],
  [["participants", "assistant", "tools", "lookup", "integration"], "assistant", "tools", "Agent assistant › Tools"],
  [["participants", "support", "connection", "number"], "support", "connection", "Human support › Connection"],
  [["participants", "caller", "connection", "number"], "$entry", "connection", "Caller › Connection"],
  [["incoming_call", "handled_by"], "$settings", "direction", "Call settings › Handled by"],
  [["defaults", "capabilities", "model_inference", "provider"], "$settings", "defaults", "Call settings › Model inference"],
  [["call_variables", "sections", "contact", "schema", "properties", "phone", "type"], "$settings", "variables", "Call settings › Variables"],
  [["wait_sounds", "call_setup"], "$settings", "wait", "Call settings › Wait sounds"],
  [["media_policy", "record_audio"], "$settings", "media", "Call settings › Media and recording"],
  [["opening_audio", "url"], "$entry", "connection", "Caller › Opening audio"],
  [["tool_visibility_overrides", "assistant", "lookup"], "$settings", "advanced", "Call settings › Tool visibility"],
] as const;
for (const [path, nodeId, tab, label] of locations) test(`issue placement: ${path.join(".")}`, () => {
  expect(locateIssue(source, [...path])).toMatchObject({ nodeId, tab, label, field: [...path] });
});

test("unknown fields and missing participants keep the backend reason and go to the issues list", () => {
  for (const path of [["new_field"], ["participants", "missing", "prompt"], ["participants", "assistant", "new_field"]]) {
    expect(locateIssue(source, path)).toBeNull();
    expect(actionOutcome(source, "save", { status: 422, error: { code: "invalid_call_spec", path, reason: "New server rule." } })).toMatchObject({ message: "Couldn't save: New server rule.", action: "show", location: null, issue: { path } });
  }
});

test("success and local rejection outcomes carry revision and first issue", () => {
  expect(actionOutcome(source, "save", { status: 201, revision: 3 })).toMatchObject({ tone: "success", message: "Saved as revision 3", persistent: false });
  expect(actionOutcome(source, "publish", { status: 200, revision: 3 })).toMatchObject({ tone: "success", message: "Published revision 3" });
  const issue = { code: "invalid_call_spec", path: ["participants", "assistant", "prompt"], reason: "is required" };
  expect(actionOutcome(source, "save", { clientIssues: [issue, issue] })).toMatchObject({ message: "Fix 2 issues before saving", action: "show", location: { nodeId: "assistant" } });
  expect(actionOutcome(source, "publish", { status: 409, error: { ...issue, code: "call_spec_not_publishable" } })).toMatchObject({ message: "Couldn't publish: Agent assistant › Prompt is required", action: "show", persistent: true });
});

const failures = [
  [422, "provider_credential_unavailable", "No usable selected provider credential for this tenant", "services"],
  [403, "provider_service_forbidden", "This tenant can't use selected provider", "services"],
  [422, "telephony_caller_id_missing", "Selected phone service has no outbound caller ID number", "services"],
  [422, "invalid_telephony_route", "The phone number isn't routable through the selected phone service", "show"],
  [422, "private_call_spec_material", "Remove credentials or secrets from Agent assistant › Prompt", "show"],
  [409, "revision_conflict", "This spec changed while saving. Reload to see the latest revision", "reload"],
  [404, "call_spec_not_found", "This call spec no longer exists", undefined],
  [403, "authoring_forbidden", "You don't have permission to change call specs", undefined],
  [401, "invalid_api_key", "Your session expired. Changes in this tab are kept until you leave the page", undefined],
  [400, "invalid_request", "Couldn't save: the editor sent an invalid request", undefined],
  [503, "call_spec_authoring_unavailable", "Couldn't save. Try again", "retry"],
  [0, "network_error", "Couldn't save. Try again", "retry"],
] as const;
for (const [status, code, message, action] of failures) test(`action outcome: ${code}`, () => {
  expect(actionOutcome(source, "save", { status, error: { code, path: ["participants", "assistant", "prompt"], reason: "server fallback" } })).toMatchObject({ tone: "error", persistent: true, message, action });
});

test("provider failures identify the selection without leaking option values", () => {
  const selected = structuredClone(source);
  selected.defaults = { capabilities: { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah", api_key: "never-show-this" } } } };
  const result = actionOutcome(selected, "save", { status: 422, error: { code: "provider_credential_unavailable", path: ["defaults", "capabilities", "text_to_speech"] } });
  expect(result.message).toBe("No usable deepgram credential for this tenant");
  expect(result.location?.tab).toBe("defaults");
  expect(JSON.stringify(result)).not.toContain("never-show-this");
});
