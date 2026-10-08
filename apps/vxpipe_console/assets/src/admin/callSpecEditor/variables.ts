import { editSource, requireIdentifier } from "./editSource";
import { agent } from "./edits";
import type { CallSpecSource, SourceDocument, VariablePermission, VariableSchema, VariableSection } from "./types";

export function addSection(document: SourceDocument, key: string, value: VariableSection = { schema: { type: "object", properties: {}, additionalProperties: false } }): SourceDocument {
  return editSource(document, (source) => {
    requireIdentifier(key);
    const variables = source.call_variables ??= {};
    const sections = variables.sections ??= {};
    if (Object.hasOwn(sections, key)) throw new Error("That section already exists.");
    variables.sections = { ...sections, [key]: structuredClone(value) };
  });
}

export function renameSection(document: SourceDocument, previous: string, next: string): SourceDocument {
  return editSource(document, (source) => {
    section(source, previous);
    requireIdentifier(next);
    if (previous === next) return;
    const sections = source.call_variables!.sections!;
    if (Object.hasOwn(sections, next)) throw new Error("That section already exists.");
    source.call_variables!.sections = renameKey(sections, previous, next);
    for (const value of Object.values(source.participants)) {
      if (value.type === "agent" && value.variable_permissions) value.variable_permissions = renameKey(value.variable_permissions, previous, next);
      if (value.type === "human" && value.connection.number_from_variable?.section === previous) value.connection.number_from_variable.section = next;
    }
  });
}

export function removeSection(document: SourceDocument, key: string): SourceDocument {
  return editSource(document, (source) => {
    section(source, key);
    delete source.call_variables!.sections![key];
    for (const value of Object.values(source.participants)) {
      if (value.type === "agent" && value.variable_permissions) delete value.variable_permissions[key];
      if (value.type === "human" && value.connection.number_from_variable?.section === key) {
        value.connection.number_from_variable = { section: "", variable: "" };
      }
    }
  });
}

export function setSectionSchema(document: SourceDocument, key: string, schema: VariableSchema): SourceDocument {
  return editSource(document, (source) => { section(source, key).schema = structuredClone(schema); });
}

export function setSectionPermission(document: SourceDocument, key: string, sectionKey: string, value: VariablePermission | undefined): SourceDocument {
  return editSource(document, (source) => {
    const target = agent(source, key);
    if (value !== undefined) section(source, sectionKey);
    const grants = target.variable_permissions ?? {};
    if (value === undefined) {
      if (target.variable_permissions) delete target.variable_permissions[sectionKey];
    } else target.variable_permissions = { ...grants, [sectionKey]: [...value] };
  });
}

export function setVariableField(document: SourceDocument, sectionKey: string, key: string, schema: VariableSchema, required: boolean): SourceDocument {
  return editSource(document, (source) => {
    const target = section(source, sectionKey).schema;
    target.properties = { ...target.properties, [key]: structuredClone(schema) };
    const names = (target.required ?? []).filter((name) => name !== key);
    if (required || target.required) target.required = required ? [...names, key] : names;
  });
}

export function renameVariableField(document: SourceDocument, sectionKey: string, previous: string, next: string): SourceDocument {
  return editSource(document, (source) => {
    const schema = section(source, sectionKey).schema;
    requireField(schema, previous);
    if (previous === next) return;
    if (Object.hasOwn(schema.properties!, next)) throw new Error("That field already exists.");
    schema.properties = renameKey(schema.properties!, previous, next);
    if (schema.required) schema.required = schema.required.map((key) => key === previous ? next : key);
    rewriteNumberReferences(source, sectionKey, previous, next);
  });
}

export function removeVariableField(document: SourceDocument, sectionKey: string, key: string): SourceDocument {
  return editSource(document, (source) => {
    const schema = section(source, sectionKey).schema;
    requireField(schema, key);
    delete schema.properties![key];
    if (schema.required) schema.required = schema.required.filter((name) => name !== key);
    rewriteNumberReferences(source, sectionKey, key, "");
  });
}

function section(source: CallSpecSource, key: string): VariableSection {
  const sections = source.call_variables?.sections;
  if (!sections || !Object.hasOwn(sections, key)) throw new Error("That variable section no longer exists.");
  return sections[key]!;
}

function requireField(schema: VariableSchema, key: string): void {
  if (!schema.properties || !Object.hasOwn(schema.properties, key)) throw new Error("That variable field no longer exists.");
}

function renameKey<T>(map: Record<string, T>, previous: string, next: string): Record<string, T> {
  return Object.fromEntries(Object.entries(map).map(([key, value]) => [key === previous ? next : key, value]));
}

function rewriteNumberReferences(source: CallSpecSource, sectionKey: string, previous: string, next: string): void {
  for (const value of Object.values(source.participants)) {
    if (value.type !== "human") continue;
    const ref = value.connection.number_from_variable;
    if (ref?.section === sectionKey && ref.variable === previous) ref.variable = next;
  }
}
