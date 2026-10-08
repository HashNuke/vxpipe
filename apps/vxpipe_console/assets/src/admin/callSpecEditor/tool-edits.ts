import { editSource, requireIdentifier } from "./editSource";
import { agent } from "./edits";
import type { SourceDocument, ToolSelection } from "./types";

export function setTool(document: SourceDocument, participantKey: string, previous: string | undefined, name: string, selection: ToolSelection): SourceDocument {
  return editSource(document, (source) => {
    requireIdentifier(name);
    requireIdentifier(selection.tool);
    if (["transfer", "read_variables", "update_variables", "update_variable"].includes(name)) throw new Error("That key is reserved for a platform tool.");
    if (selection.type === "host" && name !== selection.tool) throw new Error("Host tools must use their registered name as the local key.");
    if (selection.type === "mcp") requireIdentifier(selection.integration ?? "");
    const target = agent(source, participantKey);
    const tools = target.tools ?? {};
    if (previous !== undefined && !Object.hasOwn(tools, previous)) throw new Error("That tool no longer exists.");
    if (previous !== name && Object.hasOwn(tools, name)) throw new Error("That tool key already exists.");
    target.tools = Object.fromEntries([
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
