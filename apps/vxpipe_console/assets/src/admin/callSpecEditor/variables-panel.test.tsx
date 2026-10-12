import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
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
test("section and field renames update permissions, required membership and dial references", () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Edit section contact" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Section name" }), { target: { value: "customer" } });
  fireEvent.click(screen.getByRole("button", { name: "Save section" }));
  fireEvent.click(screen.getByRole("button", { name: "Edit customer / phone" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Name" }), { target: { value: "telephone" } });
  fireEvent.click(screen.getByRole("button", { name: "Save variable" }));
  expect(saved().participants.intake.variable_permissions).toEqual({ customer: ["read"] });
  expect(saved().participants.support.connection.number_from_variable).toEqual({ section: "customer", variable: "telephone" });
  expect(saved().call_variables.sections.customer.schema.required).toEqual(["telephone"]);
  expect(saved().participants.intake.prompt).toBe("Collect contact.phone");
});
test("enum tags use the field type and preserve hidden constraints and siblings", () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Edit contact / phone" }));
  expect(screen.queryByRole("checkbox", { name: /nullable/i })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /Constraints/ })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("checkbox", { name: "contact / phone enum" }));
  const input = screen.getByRole("textbox", { name: "contact / phone valid values" });
  fireEvent.change(input, { target: { value: "+15555550100" } });
  fireEvent.keyDown(input, { key: "Enter" });
  fireEvent.change(input, { target: { value: "+15555550200" } });
  fireEvent.keyDown(input, { key: "Enter" });
  fireEvent.click(screen.getByRole("button", { name: "Remove valid value +15555550200" }));
  expect(screen.getAllByRole("combobox")).toHaveLength(1);
  fireEvent.click(screen.getByRole("button", { name: "Save variable" }));
  expect(saved().call_variables.sections.contact.schema.properties).toEqual({ phone: { type: "string", minLength: 2, enum: ["+15555550100"] }, nested: { type: "array", items: { type: "integer", minimum: 1 } } });
});
test("call variables leaves section permissions in agent settings", () => {
  render(<Harness />);
  expect(screen.queryByText("Section permissions")).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "contact access for intake" })).not.toBeInTheDocument();
});
test("add and remove sections and fields preserve unrelated data and reject name collisions", () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Add section" }));
  const dialog = within(screen.getByRole("dialog", { name: "Add section" }));
  expect(saved()).toEqual(initial.source);
  fireEvent.click(dialog.getByRole("button", { name: "Add section" }));
  expect(dialog.getByRole("alert")).toHaveTextContent("Enter a section name");
  fireEvent.change(dialog.getByRole("textbox", { name: "Section name" }), { target: { value: "contact" } });
  fireEvent.click(dialog.getByRole("button", { name: "Add section" }));
  expect(screen.getByRole("alert")).toHaveTextContent("already exists");
  fireEvent.change(dialog.getByRole("textbox", { name: "Section name" }), { target: { value: "preferences" } });
  fireEvent.click(dialog.getByRole("button", { name: "Add section" }));
  expect(saved().call_variables.sections.preferences.schema).toEqual({ type: "object", properties: {}, additionalProperties: false });
  fireEvent.click(screen.getByRole("button", { name: "Add variable to contact" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Name" }), { target: { value: "field_1" } });
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add variable" }));
  expect(saved().call_variables.sections.contact.schema.properties.field_1).toEqual({ type: "string" });
  fireEvent.click(screen.getByRole("button", { name: "Remove contact / phone" }));
  expect(saved().call_variables.sections.contact.schema.required).toEqual([]);
  expect(saved().participants.support.connection.number_from_variable.variable).toBe("");
  fireEvent.click(screen.getByRole("button", { name: "Remove section contact" }));
  expect(saved().participants.intake.variable_permissions).toEqual({});
  expect(saved().call_variables.sections.preferences).toBeDefined();
});

test("section names and constraint tags replace inline fields, and cancelled edits leave source intact", () => {
  render(<Harness />);
  const section = within(screen.getByRole("region", { name: "Section contact" }));
  expect(section.getByRole("heading", { name: "contact" })).toBeVisible();
  expect(section.getByText('required: ["phone"]')).toHaveAttribute("data-slot", "badge");
  expect(section.queryByRole("textbox")).not.toBeInTheDocument();
  expect(section.queryByRole("combobox")).not.toBeInTheDocument();
  expect(screen.queryByText("Section constraints")).not.toBeInTheDocument();
  fireEvent.click(section.getByRole("button", { name: "Edit section contact" }));
  expect(screen.queryByRole("combobox", { name: /additional properties/i })).not.toBeInTheDocument();
  expect(screen.queryByRole("combobox", { name: "contact allowed values" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Constraints" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByRole("textbox", { name: "Section name" }), { target: { value: "changed" } });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(saved()).toEqual(initial.source);
  fireEvent.click(section.getByRole("button", { name: "Edit section contact" }));
  fireEvent.click(screen.getByRole("button", { name: "Save section" }));
  expect(saved()).toEqual(initial.source);
});

test("cancelling a new section leaves source intact", () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Add section" }));
  expect(screen.queryByRole("combobox", { name: "New section allowed values" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByRole("textbox", { name: "Section name" }), { target: { value: "unused" } });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(saved()).toEqual(initial.source);
});

test("historical section schemas open for inspection without editing", () => {
  render(<Harness readOnly />);
  fireEvent.click(screen.getByRole("button", { name: "View section contact" }));
  expect(screen.getByRole("dialog", { name: "View section" })).toBeVisible();
  expect(screen.getByRole("textbox", { name: "Section name" })).toBeDisabled();
  expect(screen.queryByRole("combobox", { name: "contact allowed values" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Save section" })).not.toBeInTheDocument();
  expect(saved()).toEqual(initial.source);
});

test("new object variables use declared fields only without an additional properties control", async () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Add variable to contact" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Name" }), { target: { value: "address" } });
  await choose("contact / new variable type", "object");
  expect(screen.queryByRole("combobox", { name: /additional properties/i })).not.toBeInTheDocument();
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add variable" }));
  expect(saved().call_variables.sections.contact.schema.properties.address).toEqual({ type: "object", additionalProperties: false });
});
test("historical variables can be inspected but not edited", () => {
  render(<Harness readOnly />);
  for (const role of ["textbox", "spinbutton", "combobox", "checkbox"] as const) for (const control of screen.queryAllByRole(role)) expect(control).toBeDisabled();
  expect(screen.getByRole("button", { name: "Add section" })).toBeDisabled();
});

test("hidden constraints survive opening and saving nested variables", () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Edit contact / nested" }));
  expect(screen.queryByRole("spinbutton")).not.toBeInTheDocument();
  expect(screen.queryByRole("checkbox", { name: /nullable/i })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Save variable" }));
  expect(saved()).toEqual(initial.source);
});

test.each(["Add variable to contact", "Add variable to section contact"])("variable modal stages additions, rejects duplicate names and discards cancelled edits from %s", (action) => {
  render(<Harness />);
  expect(screen.queryByRole("textbox", { name: "Name" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: action }));
  const dialog = within(screen.getByRole("dialog", { name: "Add variable" }));
  fireEvent.change(dialog.getByRole("textbox", { name: "Name" }), { target: { value: "phone" } });
  fireEvent.click(dialog.getByRole("button", { name: "Add variable" }));
  expect(dialog.getByRole("alert")).toHaveTextContent("already exists");
  expect(saved()).toEqual(initial.source);
  fireEvent.change(dialog.getByRole("textbox", { name: "Name" }), { target: { value: "email" } });
  fireEvent.click(dialog.getByRole("button", { name: "Add variable" }));
  expect(saved().call_variables.sections.contact.schema.properties.email).toEqual({ type: "string" });
  fireEvent.click(screen.getByRole("button", { name: "Edit contact / phone" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Name" }), { target: { value: "changed" } });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(saved().call_variables.sections.contact.schema.properties.phone).toEqual({ type: "string", minLength: 2 });
});

test("historical variable schemas open for inspection without editing", () => {
  render(<Harness readOnly />);
  fireEvent.click(screen.getByRole("button", { name: "View contact / phone" }));
  expect(screen.getByRole("dialog", { name: "View variable" })).toBeInTheDocument();
  expect(screen.getByRole("textbox", { name: "Name" })).toBeDisabled();
  expect(screen.queryByRole("spinbutton")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Save variable" })).not.toBeInTheDocument();
  expect(saved()).toEqual(initial.source);
});


test("enum input rejects duplicate and mistyped values and saves numeric tags as numbers", async () => {
  render(<Harness />);
  fireEvent.click(screen.getByRole("button", { name: "Add variable to contact" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Name" }), { target: { value: "age" } });
  await choose("contact / new variable type", "integer");
  fireEvent.click(screen.getByRole("checkbox", { name: "contact / new variable enum" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "contact / new variable required" }));
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add variable" }));
  expect(screen.getByRole("alert")).toHaveTextContent("at least one");
  const input = screen.getByRole("textbox", { name: "contact / new variable valid values" });
  const enter = (value: string) => { fireEvent.change(input, { target: { value } }); fireEvent.keyDown(input, { key: "Enter" }); };
  enter("hello");
  expect(screen.getAllByRole("alert").some(el => el.textContent?.includes("integer"))).toBe(true);
  enter("18");
  enter("18");
  expect(screen.getAllByRole("alert").some(el => el.textContent?.includes("already"))).toBe(true);
  enter("21");
  fireEvent.click(within(screen.getByRole("dialog")).getByRole("button", { name: "Add variable" }));
  expect(saved().call_variables.sections.contact.schema.properties.age).toEqual({ type: "integer", enum: [18, 21] });
  expect(saved().call_variables.sections.contact.schema.required).toContain("age");
});
