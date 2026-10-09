import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { editorFixture } from "./editorFixtures";
import { parseSource, serializeSource } from "./source";
import { createEditorState, editorReducer, isDirty } from "./editor-state";
import { retainBackendIssue } from "./issues";
import { SourceView } from "./source-view";
import { VariablesPanel } from "./variables-panel";
import { validateSource } from "./validation";

afterEach(cleanup);
const json = JSON.stringify({ ...editorFixture.source, call_variables: { sections: {
  ...editorFixture.source.call_variables?.sections,
  account: { schema: { type: "object", properties: { id: { type: "integer", enum: ["INTEGER_A", "INTEGER_B"], minimum: "INTEGER_A" } } } },
} } }).replaceAll('"INTEGER_A"', "9007199254740992").replaceAll('"INTEGER_B"', "9007199254740993");

test("source parsing, validation, revision tracking and export preserve distinct large integers", () => {
  const document = parseSource(json);
  expect(serializeSource(document)).toContain("9007199254740993");
  expect(validateSource(document.source)).toEqual([]);
  let state = createEditorState({ document, saved: { callSpecId: "large", revision: 1, publishedRevision: null } });
  expect(isDirty(state)).toBe(false);
  const issue = { code: "invalid_call_spec", path: ["call_variables"], reason: "Example error" };
  const next = { ...document, source: { ...document.source, name: "Renamed" } };
  expect(retainBackendIssue(issue, document.source, next.source)).toEqual(issue);
  state = editorReducer(state, { type: "edit", document: next });
  expect(isDirty(state)).toBe(true);
  state = editorReducer(state, { type: "start", action: "save" });
  expect(state.pending).toBeDefined();
  expect(serializeSource({ ...document, source: state.pending!.source })).toContain("9007199254740993");
  state = editorReducer(state, { type: "complete", id: state.pending!.id, result: { status: 201, callSpecId: "large", revision: 2 } });
  expect(isDirty(state)).toBe(false);
  render(<SourceView open onOpenChange={() => {}} source={state.document.source} onFeedback={() => {}} />);
  expect(screen.getByRole("textbox", { name: "Call spec JSON" })).toHaveValue(serializeSource(state.document));
});

test.each(["-9007199254740993", "999999999999999999999999999999999999", "9007199254740991"])("nested option integer %s stays numeric and exact", (integer) => {
  const raw = JSON.stringify({ ...editorFixture.source, defaults: { capabilities: { model_inference: {
    provider: "google", model: "gemini-2.5-flash", options: { values: ["EXACT"], label: "9007199254740993" },
  } } } }).replace('"EXACT"', integer);
  const serialized = serializeSource(parseSource(raw));
  expect(serialized).toContain(`\n            ${integer}\n`);
  expect(serialized).toContain('"label": "9007199254740993"');
});

test("schema controls display and edit large numeric enums and bounds without rounding", () => {
  function Harness() {
    const [document, onChange] = useState(() => parseSource(json));
    return <><VariablesPanel document={document} onChange={onChange} /><output data-testid="source">{serializeSource(document)}</output></>;
  }
  render(<Harness />);
  const field = screen.getByRole("spinbutton", { name: "account / id enum / 2" }) as HTMLInputElement;
  expect(field.value).toBe("9007199254740993");
  expect(field).toHaveAttribute("aria-valuetext", "9007199254740993");
  fireEvent.change(field, { target: { value: "-9007199254740995" } });
  fireEvent.change(screen.getByRole("spinbutton", { name: "account / id minimum" }), { target: { value: "-9007199254740997" } });
  const source = screen.getByTestId("source").textContent!;
  expect(source).toContain("-9007199254740995");
  expect(source).toContain('"minimum": -9007199254740997');
  expect(validateSource(parseSource(source).source)).toEqual([]);
});

test("large non-negative schema length limits remain valid, but negative limits are rejected", () => {
  const raw = json.replace('"minimum":9007199254740992', '"maxLength":9007199254740993');
  expect(validateSource(parseSource(raw).source)).toEqual([]);
  expect(validateSource(parseSource(raw.replace('"maxLength":9007199254740993', '"maxLength":-9007199254740993')).source))
    .toContainEqual(expect.objectContaining({ path: ["call_variables", "sections", "account", "schema", "properties", "id", "maxLength"] }));
});
