import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { VariablesPanel } from "./variables-panel";
import { editorFixture } from "./editorFixtures";
import type { SourceDocument } from "./types";
afterEach(cleanup);
const initial: SourceDocument = { ...editorFixture, source: { ...editorFixture.source,
  call_variables: { sections: { contact: { schema: { type: "object", properties: { phone: { type: "string", minLength: 2 }, nested: { type: "array", items: { type: "integer", minimum: 1 } } }, required: ["phone"], additionalProperties: false } } } },
  participants: { ...editorFixture.source.participants,
    intake: { type: "agent", prompt: "Collect contact.phone", variable_permissions: { contact: ["read"] } },
    support: { type: "human", connection: { service: "phone", mode: "dial", number_from_variable: { section: "contact", variable: "phone" } } },
  },
} };
function Harness({ readOnly = false, initialDocument = initial }: { readOnly?: boolean; initialDocument?: SourceDocument }) {
  const [document, onChange] = useState({ ...initialDocument, readOnly });
  return <><VariablesPanel document={document} onChange={onChange} /><output data-testid="source">{JSON.stringify(document.source)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("source").textContent!);
async function choose(label: string, value: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: value }));
}
function rename(label: string, next: string) {
  const field = screen.getByRole("textbox", { name: label });
  fireEvent.change(field, { target: { value: next } }); fireEvent.blur(field);
}
test("section and field renames update permissions, required membership and dial references", () => {
  render(<Harness />);
  rename("Section contact name", "customer");
  rename("customer / phone name", "telephone");
  expect(saved().participants.intake.variable_permissions).toEqual({ customer: ["read"] });
  expect(saved().participants.support.connection.number_from_variable).toEqual({ section: "customer", variable: "telephone" });
  expect(saved().call_variables.sections.customer.schema.required).toEqual(["telephone"]);
  expect(saved().participants.intake.prompt).toBe("Collect contact.phone");
});
test("nested schemas, nullable types, enums and constraints are editable without resetting siblings", async () => {
  render(<Harness />);
  fireEvent.change(screen.getByRole("spinbutton", { name: "contact / nested / items minimum" }), { target: { value: "3" } });
  fireEvent.click(screen.getByRole("checkbox", { name: "contact / phone nullable" }));
  await choose("contact / phone allowed values", "Enumeration");
  fireEvent.change(screen.getByRole("textbox", { name: "contact / phone enum / 1" }), { target: { value: "+15555550100" } });
  expect(saved().call_variables.sections.contact.schema.properties).toEqual({ phone: { type: ["string", "null"], minLength: 2, enum: ["+15555550100"] }, nested: { type: "array", items: { type: "integer", minimum: 3 } } });
});
test("section permission matrix exposes read and read-write with inline validation paths", async () => {
  render(<Harness />);
  await choose("contact access for intake", "Read and write");
  expect(saved().participants.intake.variable_permissions.contact).toEqual(["read", "write"]);
  await choose("contact access for intake", "No access");
  expect(saved().participants.intake.variable_permissions).toEqual({});
});
test("add and remove sections and fields preserve unrelated data and reject name collisions", () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Add section" }));
  expect(saved().call_variables.sections.section_1.schema.type).toBe("object");
  rename("Section section_1 name", "contact");
  expect(screen.getByRole("alert")).toHaveTextContent("already exists");
  fireEvent.click(screen.getByRole("button", { name: "Add contact field" }));
  expect(saved().call_variables.sections.contact.schema.properties.field_1).toEqual({ type: "string" });
  fireEvent.click(screen.getByRole("button", { name: "Remove contact / phone" }));
  expect(saved().call_variables.sections.contact.schema.required).toEqual([]);
  expect(saved().participants.support.connection.number_from_variable.variable).toBe("");
  fireEvent.click(screen.getByRole("button", { name: "Remove section contact" }));
  expect(saved().participants.intake.variable_permissions).toEqual({});
  expect(saved().call_variables.sections.section_1).toBeDefined();
});
test("historical variables can be inspected but not edited", () => {
  render(<Harness readOnly />);
  for (const role of ["textbox", "spinbutton", "combobox", "checkbox"] as const) for (const control of screen.getAllByRole(role)) expect(control).toBeDisabled();
  expect(screen.getByRole("button", { name: "Add section" })).toBeDisabled();
});

test("saved grants for missing sections remain visible and can be cleared", async () => {
  render(<Harness initialDocument={{ ...initial, source: { ...initial.source, call_variables: { sections: {} } } }} />);
  expect(screen.getByRole("combobox", { name: "contact access for intake" })).toHaveTextContent("Read");
  await choose("contact access for intake", "No access");
  expect(saved().participants.intake.variable_permissions).toEqual({});
});

test("constraint controls follow the field type while retaining unusual stored constraints", () => {
  const configured = structuredClone(initial);
  configured.source.call_variables!.sections!.contact!.schema.properties!.nested!.items!.minLength = 5;
  render(<Harness initialDocument={configured} />);
  expect(screen.getByRole("spinbutton", { name: "contact / phone minLength" })).toHaveValue(2);
  expect(screen.queryByRole("spinbutton", { name: "contact / phone minimum" })).not.toBeInTheDocument();
  expect(screen.getByRole("spinbutton", { name: "contact / nested / items minLength" })).toHaveValue(5);
});
