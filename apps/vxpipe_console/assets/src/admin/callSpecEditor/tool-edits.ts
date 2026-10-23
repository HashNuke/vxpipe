import { editSource, requireIdentifier } from "./editSource";
import { agent } from "./edits";
import type { SourceDocument, ToolSelection } from "./types";

const reservedNames = new Set(["transfer", "read_variables", "update_variables", "update_variable"]);
export const toolIdentity = (tool: Pick<ToolSelection, "type" | "tool" | "integration">) => JSON.stringify([tool.type, tool.integration ?? "", tool.tool]);
export const registeredToolName = (tool: Pick<ToolSelection, "type" | "tool" | "integration">) => tool.type === "mcp" ? `${tool.integration}__${tool.tool}` : tool.tool;

export function registeredToolNameIssue(name: string): string | undefined {
  if (name.length > 64) return "Name exceeds 64 characters";
  if (!/^[A-Za-z_][A-Za-z0-9_]*(-[A-Za-z0-9_]+)*$/.test(name)) return "Unsupported name format";
}

// Build the whole change before publishing it so a failed addition never leaves a partial batch.
export function addTools(document: SourceDocument, participantKey: string, selections: ToolSelection[]): SourceDocument {
  const unique = [...new Map(selections.map((selection) => [toolIdentity(selection), selection])).values()];
  return unique.reduce((draft, selection) => setTool(draft, participantKey, undefined, registeredToolName(selection), selection), document);
}

export function setTool(document: SourceDocument, participantKey: string, previous: string | undefined, name: string, selection: ToolSelection): SourceDocument {
  return editSource(document, (source) => {
    if (selection.type === "mcp" && name !== previous) {
      const issue = registeredToolNameIssue(name);
      if (issue) throw new Error(issue);
    }
    requireIdentifier(name);
    requireIdentifier(selection.tool);
    if (reservedNames.has(name)) throw new Error("That key is reserved for a platform tool.");
    if (selection.type === "host" && name !== selection.tool) throw new Error("Host tools must use their registered name as the local key.");
    if (selection.type === "mcp") requireIdentifier(selection.integration ?? "");
    const target = agent(source, participantKey);
    const tools = target.tools ?? {};
    if (previous !== undefined && !Object.hasOwn(tools, previous)) throw new Error("That tool no longer exists.");
    if (previous !== name && Object.hasOwn(tools, name)) throw new Error("That tool key already exists.");
    target.tools = previous === name ? { ...tools, [name]: structuredClone(selection) } : Object.fromEntries([
      ...Object.entries(tools).filter(([key]) => key !== previous),
      [name, structuredClone(selection)],
    ]);
    const overrides = source.tool_visibility_overrides;
    const visibility = overrides && Object.hasOwn(overrides, participantKey) ? overrides[participantKey] : undefined;
    if (previous !== undefined && previous !== name && visibility && Object.hasOwn(visibility, previous)) {
      overrides![participantKey] = Object.fromEntries(Object.entries(visibility).filter(([key]) => key !== name).map(([key, value]) => [key === previous ? name : key, value]));
    }
  });
}
