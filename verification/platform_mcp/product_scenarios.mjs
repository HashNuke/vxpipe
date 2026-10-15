import assert from "node:assert/strict";
import { isDeepStrictEqual } from "node:util";

export const allTools = [
  "list_tenants", "get_tenant", "list_call_specs", "get_call_spec", "create_call_spec",
  "update_call_spec", "publish_call_spec_revision", "list_providers", "list_provider_models",
  "create_call", "create_join_token", "hangup_call", "list_users", "list_role_options",
  "create_user", "update_user", "disable_user"
].sort();
export const callTools = ["list_tenants", "get_tenant", "create_call", "create_join_token", "hangup_call"].sort();
export const tenantTools = allTools.filter(name => !["list_users", "list_role_options", "create_user", "update_user", "disable_user"].includes(name));
const password = "synthetic-sdk-user-password!";

function safeResult(result, name, secrets, progress) {
  progress(`${name} success status`);
  assert.equal(result.isError, false, `${name} failed`);
  progress(`${name} structured result`);
  const value = result.structuredContent;
  assert.ok(value && typeof value === "object", `${name} has no structured result`);
  assert.ok(result.content.length === 1 && result.content[0].type === "text", `${name} content shape`);
  progress(`${name} content parity`);
  assert.ok(isDeepStrictEqual(JSON.parse(result.content[0].text), value), `${name} content parity`);
  progress(`${name} redaction`);
  const json = JSON.stringify(value);
  assert.ok(![password, ...secrets].some(secret => json.includes(secret)), `${name} exposed private input`);
  const forbidden = new Set(["password", "password_hash", "api_key", "resolved_plan", "plan_digest", "digest", "credential_payload"]);
  function visit(node) {
    if (!node || typeof node !== "object") return;
    for (const [key, child] of Object.entries(node)) {
      assert.ok(!forbidden.has(key), `${name} exposed a private field`);
      visit(child);
    }
  }
  visit(value);
  progress(`${name} result contract`);
  return value;
}

export async function exerciseProducts(client, { tenant, mount, secrets, progress }) {
  const exercised = new Set();
  async function tool(name, args = {}) {
    progress(name);
    exercised.add(name);
    let result;
    try { result = await client.callTool({ name, arguments: args }); }
    catch { throw new Error(`${mount}: ${name} request failed`); }
    return safeResult(result, name, secrets, progress);
  }
  const tenants = await tool("list_tenants", { page_size: 1 });
  assert.ok(tenants.items.length === 1 && tenants.pagination.page_size === 1);
  const detail = await tool("get_tenant", { tenant_key: tenant });
  assert.equal(detail.tenant_key, tenant);

  const source = {
    schema_version: "20261004.01", name: `SDK ${mount}`,
    incoming_call: { caller: "caller", handled_by: "assistant" },
    call_variables: { sections: { order: { schema: { type: "object", properties: { id: { type: "string" } } } } } },
    defaults: { capabilities: { model_inference: { provider: "fixture", model: "test" } } },
    participants: {
      caller: { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } },
      assistant: { type: "agent", prompt: "Synthetic acceptance only; no provider invocation." }
    }
  };
  const draft = await tool("create_call_spec", { tenant_key: tenant, call_spec_definition: source });
  assert.equal(draft.revision, 1);
  const identity = { tenant_key: tenant, call_spec_id: draft.call_spec_id };
  const revised = await tool("update_call_spec", { ...identity, call_spec_definition: { ...source, name: `${source.name} revised` } });
  assert.equal(revised.revision, 2);
  const published = await tool("publish_call_spec_revision", { ...identity, revision: 2 });
  assert.equal(published.published_revision, 2);
  const historical = await tool("get_call_spec", { ...identity, revision: 1 });
  assert.equal(historical.call_spec_definition.name, source.name);
  assert.equal(historical.published_revision, 2);
  const specs = await tool("list_call_specs", { tenant_key: tenant, page_size: 50 });
  assert.ok(specs.items.some(item => item.call_spec_id === draft.call_spec_id && item.latest_revision === 2));
  const providers = await tool("list_providers", { tenant_key: tenant, capability: "text_to_speech", page_size: 1 });
  assert.equal(providers.items.length, 1);
  const models = await tool("list_provider_models", { tenant_key: tenant, provider: "morse", capability: "text_to_speech" });
  assert.ok(models.items.length > 0);

  const create = { ...identity, variables: { order: { id: "synthetic-private-variable" } }, idempotency_key: `sdk-${mount}` };
  const call = await tool("create_call", create);
  assert.deepEqual(Object.keys(call), ["call_id"]);
  const replay = await tool("create_call", create);
  assert.equal(replay.call_id, call.call_id);
  const callIdentity = { tenant_key: tenant, call_id: call.call_id };
  const token = await tool("create_join_token", callIdentity);
  assert.ok(Object.keys(token).sort().join(",") === "call_id,expires_at,participant_key,token", "Token result fields");
  assert.ok(token.call_id === call.call_id && token.token.startsWith("vxj_"), "Pinned token identity");
  secrets.push(token.token);
  const ended = await tool("hangup_call", callIdentity);
  assert.equal(ended.status, "ended");
  assert.equal(ended.call_id, call.call_id);
  assert.equal((await tool("hangup_call", callIdentity)).status, "ended");

  const roles = await tool("list_role_options", { page_size: 50 });
  assert.ok(roles.items.every(role => Object.keys(role).sort().join(",") === "kind,name,role_id"), "Safe role fields");
  const role = roles.items.find(item => item.kind === null);
  assert.ok(role, "An assignable custom role exists");
  const email = `sdk-${mount}@example.test`;
  const created = await tool("create_user", { email, password, password_confirmation: password,
    role_id: role.role_id, memberships: [{ tenant_key: tenant, access: "read_write" }] });
  assert.equal(created.enabled, true);
  const userIdentity = { user_id: created.user_id };
  assert.equal((await tool("disable_user", userIdentity)).enabled, false);
  const changed = await tool("update_user", { ...userIdentity, email: `updated-${email}` });
  assert.equal(changed.enabled, false);
  assert.equal(changed.role_id, role.role_id);
  assert.deepEqual(changed.memberships, [{ tenant_key: tenant, access: "read_write" }]);
  assert.equal((await tool("update_user", { ...userIdentity, enabled: true })).enabled, true);
  const users = await tool("list_users", { query: `updated-${email}`, page_size: 1 });
  assert.equal(users.items.length, 1);
  assert.equal(users.items[0].user_id, created.user_id);
  assert.deepEqual([...exercised].sort(), allTools);
}
