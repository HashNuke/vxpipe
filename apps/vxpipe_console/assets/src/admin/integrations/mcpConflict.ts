import { parseMcpConnection } from "./inventoryApi";
export type McpConflict = { kind: "reconnect"; id: string; generation: number } | { kind: "manage"; id: string };
const object = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);
export function parseMcpConflict(body: unknown): McpConflict | null {
  if (!object(body) || !object(body.error)) return null;
  const error = body.error;
  if (typeof error.connection_id !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(error.connection_id)) return null;
  if (error.code === "mcp_connection_exists") return { kind: "manage", id: error.connection_id };
  if (error.code === "mcp_reconnect_required" && Number.isSafeInteger(error.generation) && Number(error.generation) > 0)
    return { kind: "reconnect", id: error.connection_id, generation: Number(error.generation) };
  return null;
}
export function conflictUrl(tenant: string, conflict: McpConflict) {
  const base = `/api/tenants/${encodeURIComponent(tenant)}/mcp-connections/${encodeURIComponent(conflict.id)}`;
  return `${base}${conflict.kind === "reconnect" ? `?retained_generation=${conflict.generation}` : ""}`;
}
export function parseConflictConnection(body: unknown, tenant: string, conflict: McpConflict) {
  if (!object(body)) throw new Error("Invalid connection");
  const connection = parseMcpConnection(body.connection, tenant, conflict.kind === "reconnect");
  if (connection.id !== conflict.id || (conflict.kind === "reconnect"
    ? !connection.canEdit || connection.status !== "revoked" || connection.generation !== conflict.generation : connection.status === "revoked")) throw new Error("Connection changed");
  return connection;
}
