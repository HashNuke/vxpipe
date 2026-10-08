import type { CatalogCapability } from "../modelCatalog";
import { editSource, requireIdentifier } from "./editSource";
import type { AgentParticipant, CallSpecSource, CapabilitySelection, FirstMessage, MediaPolicy, Participant, SourceDocument, ToolSelection, WaitSounds } from "./types";

export function participant(source: CallSpecSource, key: string): Participant {
  if (!Object.hasOwn(source.participants, key)) throw new Error("That participant no longer exists.");
  return source.participants[key]!;
}

export function agent(source: CallSpecSource, key: string): AgentParticipant {
  const value = participant(source, key);
  if (value.type !== "agent") throw new Error("Choose an agent participant.");
  return value;
}

export function switchDirection(document: SourceDocument, direction: "incoming" | "outgoing", service?: string): SourceDocument {
  return editSource(document, (source) => {
    if ((direction === "incoming" && source.incoming_call) || (direction === "outgoing" && source.outgoing_call)) return;
    const key = source.incoming_call?.caller ?? source.outgoing_call?.callee;
    const handler = source.incoming_call?.handled_by ?? source.outgoing_call?.handled_by;
    if (!key || !handler) throw new Error("Choose an entry participant and handler first.");
    const entry = participant(source, key);
    if (entry.type !== "human") throw new Error("The entry participant must be human.");
    if (direction === "outgoing") {
      if (!service || service === "web") throw new Error("Choose a phone service for outgoing calls.");
      requireIdentifier(service);
      agent(source, handler);
      const number = entry.connection.number;
      entry.connection = { service, mode: "dial", admission: "start_call", ...(number ? { number } : {}) };
      delete source.incoming_call;
      source.outgoing_call = { callee: key, handled_by: handler };
    } else {
      entry.connection = { service: "web", mode: "receive", admission: "start_call" };
      delete source.outgoing_call;
      source.incoming_call = { caller: key, handled_by: handler };
    }
  });
}

export function setCapability(document: SourceDocument, key: string | null, kind: CatalogCapability, selection: CapabilitySelection | undefined): SourceDocument {
  return editSource(document, (source) => {
    const owner = key === null ? (source.defaults ??= {}) : participant(source, key);
    const capabilities = owner.capabilities ??= {};
    if (selection === undefined) delete capabilities[kind];
    else capabilities[kind] = structuredClone(selection);
    if (!Object.keys(capabilities).length) delete owner.capabilities;
    if (source.defaults && !Object.keys(source.defaults).length) delete source.defaults;
  });
}

export function setFirstMessage(document: SourceDocument, key: string, value: FirstMessage | undefined): SourceDocument {
  return editSource(document, (source) => {
    const target = agent(source, key);
    if (value === undefined) delete target.first_message;
    else target.first_message = structuredClone(value);
  });
}

export function setTools(document: SourceDocument, key: string, tools: Record<string, ToolSelection>): SourceDocument {
  return editSource(document, (source) => {
    const target = agent(source, key);
    const removed = Object.keys(target.tools ?? {}).filter((name) => !Object.hasOwn(tools, name));
    target.tools = structuredClone(tools);
    const visibility = source.tool_visibility_overrides;
    if (visibility && Object.hasOwn(visibility, key)) {
      for (const name of removed) delete visibility[key]![name];
    }
  });
}

export function setWaitSounds(document: SourceDocument, value: WaitSounds | undefined): SourceDocument {
  return editSource(document, (source) => {
    if (value === undefined) delete source.wait_sounds;
    else source.wait_sounds = structuredClone(value);
  });
}

export function setMediaPolicy(document: SourceDocument, key: string | null, value: MediaPolicy | undefined): SourceDocument {
  return editSource(document, (source) => {
    if (key === null) {
      if (value === undefined) delete source.media_policy;
      else source.media_policy = structuredClone(value);
    } else {
      const target = participant(source, key);
      if (value === undefined) delete target.while_present;
      else target.while_present = structuredClone(value);
    }
  });
}
