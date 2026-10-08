import { expect, test } from "vitest";
import { parseSource } from "./source";
import { addSection, removeSection, renameSection, setSectionSchema, setSectionPermission, setVariableField, renameVariableField, removeVariableField } from "./variables";

function document() {
  return parseSource(JSON.stringify({ schema_version: "20261004.01", incoming_call: { caller: "caller", handled_by: "assistant" }, participants: {
    caller: { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } },
    assistant: { type: "agent", prompt: "Keep contact.phone literally.", variable_permissions: { contact: ["read", "write"] } },
    support: { type: "human", connection: { service: "office", mode: "dial", number_from_variable: { section: "contact", variable: "phone" } } },
  }, call_variables: { sections: { contact: { schema: { type: "object", properties: { phone: { type: "string" }, notes: { type: "string" } }, required: ["phone"], additionalProperties: false } } } } }));
}

test("renaming sections and fields updates grants, required fields and dial references without changing literal text", () => {
  const original = document();
  const section = renameSection(original, "contact", "customer");
  const edited = renameVariableField(section, "customer", "phone", "telephone");
  expect(edited.source.call_variables?.sections?.customer?.schema.required).toEqual(["telephone"]);
  expect(edited.source.call_variables?.sections?.customer?.schema.properties).toEqual({ telephone: { type: "string" }, notes: { type: "string" } });
  expect(edited.source.participants.assistant).toMatchObject({ variable_permissions: { customer: ["read", "write"] }, prompt: "Keep contact.phone literally." });
  expect(edited.source.participants.support).toMatchObject({ connection: { number_from_variable: { section: "customer", variable: "telephone" } } });
  expect(original).toEqual(document());
});

test("removing a referenced field or section leaves an explicit required destination choice", () => {
  const removed = removeVariableField(document(), "contact", "phone");
  expect(removed.source.call_variables?.sections?.contact?.schema.required).toEqual([]);
  expect(removed.source.participants.support).toMatchObject({ connection: { number_from_variable: { section: "contact", variable: "" } } });
  const section = removeSection(document(), "contact");
  expect(section.source.call_variables?.sections).toEqual({});
  expect(section.source.participants.assistant).toMatchObject({ variable_permissions: {} });
  expect(section.source.participants.support).toMatchObject({ connection: { number_from_variable: { section: "", variable: "" } } });
});

test("section and field edits reject collisions, maintain required membership and preserve nested schemas", () => {
  const nested = { type: "object" as const, properties: { nested: { type: "array" as const, items: { type: "integer" as const } } } };
  let edited = addSection(document(), "case", { schema: nested });
  edited = setVariableField(edited, "case", "id", { type: "string", minLength: 1 }, true);
  edited = setVariableField(edited, "case", "id", { type: "string" }, true);
  expect(edited.source.call_variables?.sections?.case?.schema.required).toEqual(["id"]);
  expect(edited.source.call_variables?.sections?.case?.schema.properties?.nested).toEqual(nested.properties.nested);
  expect(() => addSection(edited, "case")).toThrow();
  expect(() => renameSection(edited, "contact", "case")).toThrow();
  expect(() => renameVariableField(edited, "contact", "phone", "notes")).toThrow();
  expect(() => setVariableField(edited, "missing", "id", {}, false)).toThrow();
  expect(() => addSection(edited, "bad name")).toThrow();
  expect(setSectionSchema(edited, "case", { type: "object" }).source.call_variables?.sections?.case?.schema).toEqual({ type: "object" });
});

test("permissions select read or read-write, and clearing a permission omits that grant", () => {
  let edited = setSectionPermission(document(), "assistant", "contact", ["read"]);
  expect(edited.source.participants.assistant).toMatchObject({ variable_permissions: { contact: ["read"] } });
  edited = setSectionPermission(edited, "assistant", "contact", undefined);
  expect(edited.source.participants.assistant).toMatchObject({ variable_permissions: {} });
  expect(() => setSectionPermission(edited, "caller", "contact", ["read"])).toThrow("agent");
  expect(() => setSectionPermission(edited, "assistant", "absent", ["read"])).toThrow();
});

test("JSON Schema property names stay lossless even when they are not participant identifiers", () => {
  let edited = setVariableField(document(), "contact", "Customer name", { type: "string" }, true);
  edited = renameVariableField(edited, "contact", "Customer name", "__proto__");
  expect(Object.hasOwn(edited.source.call_variables!.sections!.contact!.schema.properties!, "__proto__")).toBe(true);
  expect(edited.source.call_variables?.sections?.contact?.schema.required).toContain("__proto__");
});

test("an obsolete section grant can be cleared without adding its missing section", () => {
  const doc = document();
  delete doc.source.call_variables!.sections!.contact;
  const edited = setSectionPermission(doc, "assistant", "contact", undefined);
  expect(edited.source.participants.assistant).toMatchObject({ variable_permissions: {} });
  expect(() => setSectionPermission(doc, "assistant", "contact", ["read"])).toThrow();
});
