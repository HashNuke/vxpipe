import { stringifySourceJson } from "./source-json";
import { Fields, record, type ObjectValue } from "./validationFields";

const types = ["array", "boolean", "integer", "null", "number", "object", "string"];
const integers = ["maxItems", "maxLength", "minItems", "minLength"];
const numbers = ["exclusiveMaximum", "exclusiveMinimum", "maximum", "minimum"];
const keywords = ["additionalProperties", "enum", "items", "properties", "required", "type", ...integers, ...numbers];

export function validateVariables(fields: Fields, source: ObjectValue, participants: ObjectValue): void {
  const variables = source.call_variables === undefined ? {} : fields.object(source.call_variables, ["call_variables"], ["sections"]);
  const sections = variables.sections === undefined ? {} : fields.object(variables.sections, ["call_variables", "sections"]);
  for (const [key, value] of Object.entries(sections)) {
    const path = ["call_variables", "sections", key];
    fields.identifier(key, path);
    const section = fields.object(value, path, ["schema"]);
    if (!record(section.schema) || section.schema.type !== "object") fields.issue([...path, "schema", "type"], "must be object");
    schema(fields, section.schema, [...path, "schema"]);
  }
  for (const [key, value] of Object.entries(participants)) {
    if (!record(value)) continue;
    if (value.type === "agent" && value.variable_permissions !== undefined) {
      const path = ["participants", key, "variable_permissions"];
      for (const [section, grant] of Object.entries(fields.object(value.variable_permissions, path))) {
        const location = [...path, section];
        fields.identifier(section, location);
        if (!Array.isArray(grant) || !grant.includes("read") || grant.some((permission) => permission !== "read" && permission !== "write") || new Set(grant).size !== grant.length) fields.issue(location, "must grant read or read and write without duplicates");
        if (!Object.hasOwn(sections, section)) fields.issue(location, "must reference a declared Call Variables section");
      }
    }
    if (value.type === "human" && record(value.connection) && record(value.connection.number_from_variable)) dialReference(fields, key, value.connection.number_from_variable, sections, participants);
  }
}

function schema(fields: Fields, value: unknown, path: string[]): void {
  const node = fields.object(value, path, keywords);
  const type = node.type;
  if (type !== undefined && type !== null && !(typeof type === "string" && types.includes(type)) && !(Array.isArray(type) && type.length === 2 && new Set(type).size === 2 && type.includes("null") && type.every((item) => typeof item === "string" && types.includes(item)))) fields.issue([...path, "type"], "must be one supported type or one nullable type");
  if (node.required !== undefined && (!Array.isArray(node.required) || node.required.some((name) => typeof name !== "string") || new Set(node.required).size !== node.required.length)) fields.issue([...path, "required"], "must contain unique string names");
  if (Object.hasOwn(node, "additionalProperties") && node.additionalProperties !== false) fields.issue([...path, "additionalProperties"], "must be false");
  if (Object.hasOwn(node, "enum")) {
    if (!Array.isArray(node.enum) || !node.enum.length) fields.issue([...path, "enum"], "must be a non-empty array");
    else if (new Set(node.enum.map(canonical)).size !== node.enum.length) fields.issue([...path, "enum"], "must contain unique JSON values");
  }
  for (const keyword of integers) if (Object.hasOwn(node, keyword)) {
    const value = node[keyword];
    if (typeof value === "bigint" ? value < 0n : typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) fields.issue([...path, keyword], "must be a non-negative integer");
  }
  for (const keyword of numbers) if (Object.hasOwn(node, keyword) && (typeof node[keyword] !== "bigint" && (typeof node[keyword] !== "number" || !Number.isFinite(node[keyword])))) fields.issue([...path, keyword], "must be a number");
  if (node.properties !== undefined) for (const [key, child] of Object.entries(fields.object(node.properties, [...path, "properties"]))) schema(fields, child, [...path, "properties", key]);
  if (Object.hasOwn(node, "items")) schema(fields, node.items, [...path, "items"]);
}

function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (record(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return stringifySourceJson(value)!;
}

function dialReference(fields: Fields, key: string, ref: ObjectValue, sections: ObjectValue, participants: ObjectValue): void {
  const path = ["participants", key, "connection", "number_from_variable"];
  if (typeof ref.section !== "string" || !Object.hasOwn(sections, ref.section)) { fields.issue([...path, "section"], "must reference a declared Call Variables section"); return; }
  const section = sections[ref.section];
  const properties = record(section) && record(section.schema) && record(section.schema.properties) ? section.schema.properties : {};
  const variable = typeof ref.variable === "string" && Object.hasOwn(properties, ref.variable) ? properties[ref.variable] : undefined;
  if (!record(variable)) fields.issue([...path, "variable"], "must reference a declared Call Variable");
  else if (variable.type !== "string" && !(Array.isArray(variable.type) && variable.type.includes("string"))) fields.issue([...path, "variable"], "must reference a string-compatible Call Variable");
  for (const [agent, value] of Object.entries(participants)) {
    if (!record(value) || value.type !== "agent" || !record(value.variable_permissions)) continue;
    const grant = Object.hasOwn(value.variable_permissions, ref.section) ? value.variable_permissions[ref.section] : undefined;
    if (Array.isArray(grant) && grant.includes("write")) fields.issue(["participants", agent, "variable_permissions", ref.section], "must not grant write access to a dial-routing section");
  }
}
