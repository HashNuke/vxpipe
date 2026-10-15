// Opt-in wire acceptance. All credentials and tenant records are synthetic.
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";

const version = "2025-11-25";
assert.equal(process.argv.length, 2, "Usage: bin/test-platform-mcp");
const key = "platform-mcp-synthetic";
const tenant = "MCPFIXTURE000001";
const cache = execFileSync("npm", ["config", "get", "cache"], { encoding: "utf8" }).trim();
const fixtures = new Set();
const clients = new Set();
const temporary = await mkdtemp(path.join(os.tmpdir(), "vxpipe-platform-mcp-"));
let proxy;

async function cachedPackage(name, wanted) {
  for (const entry of await readdir(path.join(cache, "_npx")).catch(() => [])) {
    const root = path.join(cache, "_npx", entry, "node_modules", name);
    try {
      const manifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
      if (manifest.version === wanted) return root;
    } catch { /* Other cached npm executions need not contain this package. */ }
  }
  throw new Error(`Cache ${name}@${wanted} first; see docs/development/platform-mcp-acceptance.md`);
}

function deadline(promise, label, milliseconds = 30_000) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${label} timed out`)), milliseconds); })
  ]).finally(() => clearTimeout(timer));
}

async function startFixture(port = 0, ttl = 60) {
  const child = spawn("mix", ["run", "--no-start", "--no-compile", "verification/platform_mcp/fixture.exs", String(port), String(ttl)], {
    env: { ...process.env, MIX_ENV: "test" }, stdio: ["pipe", "pipe", "pipe"]
  });
  fixtures.add(child);
  const exit = once(child, "exit");
  let logs = "";
  let pending;
  const ready = new Promise((resolve, reject) => { pending = { resolve, reject }; });
  const lines = createInterface({ input: child.stdout });
  child.stderr.on("data", chunk => { logs = (logs + chunk).slice(-6000); });
  lines.on("line", line => {
    if (line.startsWith("PLATFORM_MCP ")) {
      const result = JSON.parse(line.slice(13));
      const waiter = pending;
      pending = undefined;
      waiter?.resolve(result);
    } else logs = (logs + line + "\n").slice(-6000);
  });
  child.on("error", error => pending?.reject(error));
  child.on("exit", code => pending?.reject(new Error(`Fixture exited ${code}: ${logs}`)));
  const fixture = {
    child,
    async command(value) {
      assert.equal(pending, undefined);
      const reply = new Promise((resolve, reject) => { pending = { resolve, reject }; });
      child.stdin.write(JSON.stringify(value) + "\n");
      return deadline(reply, "Fixture command");
    },
    async stop() {
      child.stdin.end();
      await deadline(exit, "Fixture shutdown");
      fixtures.delete(child);
    }
  };
  fixture.addresses = await deadline(ready, "Fixture startup");
  return fixture;
}

async function rpc(url, session, secret = key, method = "ping", params = {}) {
  const headers = { "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": version };
  if (secret) headers.authorization = `Bearer ${secret}`;
  if (session) headers["mcp-session-id"] = session;
  const response = await fetch(url, {
    method: "POST", headers,
    body: JSON.stringify({ jsonrpc: "2.0", id: crypto.randomUUID(), method, params }),
    signal: AbortSignal.timeout(10_000)
  });
  const body = await response.json();
  return { status: response.status, body };
}

async function officialScenarios(cli, upstream) {
  // The pinned CLI has no custom-header option. Forward bytes unchanged and add
  // only our synthetic credential; this is not authentication conformance.
  proxy = http.createServer((incoming, outgoing) => {
    const request = http.request(upstream, {
      method: incoming.method,
      headers: { ...incoming.headers, host: new URL(upstream).host, authorization: `Bearer ${key}` }
    }, response => {
      outgoing.writeHead(response.statusCode, response.headers);
      response.pipe(outgoing);
    });
    request.on("error", () => { outgoing.writeHead(502); outgoing.end(); });
    request.setTimeout(10_000, () => request.destroy());
    incoming.pipe(request);
  });
  proxy.listen(0, "127.0.0.1");
  await once(proxy, "listening");
  for (const scenario of ["server-initialize", "ping", "tools-list"]) {
    const child = spawn(process.execPath, [cli, "server", "--url", `http://127.0.0.1:${proxy.address().port}/mcp`, "--scenario", scenario, "--spec-version", version, "--output-dir", temporary], { stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", chunk => { output += chunk; });
    child.stderr.on("data", chunk => { output += chunk; });
    try {
      const [code] = await deadline(once(child, "exit"), scenario);
      assert.equal(code, 0, output);
    } finally { if (child.exitCode === null) child.kill("SIGKILL"); }
    console.log(`PASS official ${scenario} (synthetic-header proxy)`);
  }
  proxy.closeAllConnections();
  await new Promise(resolve => proxy.close(resolve));
  proxy = undefined;
}

try {
  const sdk = await cachedPackage("@modelcontextprotocol/sdk", "1.30.0");
  const harness = await cachedPackage("@modelcontextprotocol/conformance", "0.1.16");
  const { Client } = await import(pathToFileURL(path.join(sdk, "dist/esm/client/index.js")));
  const { StreamableHTTPClientTransport } = await import(pathToFileURL(path.join(sdk, "dist/esm/client/streamableHttp.js")));
  async function connect(url, secret = key) {
    const client = new Client({ name: "vxpipe-platform-acceptance", version: "1" });
    clients.add(client);
    const transport = new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers: { Authorization: `Bearer ${secret}` } } });
    await deadline(client.connect(transport), "SDK initialization");
    assert.equal(transport.protocolVersion, version);
    assert.ok(transport.sessionId);
    return { client, transport };
  }

  const fixture = await startFixture();
  for (const [mount, url] of Object.entries(fixture.addresses)) {
    const { client, transport } = await connect(url);
    const catalog = await client.listTools();
    assert.ok(catalog.tools.some(tool => tool.name === "list_tenants"));
    const result = await client.callTool({ name: "list_tenants", arguments: {} });
    assert.equal(result.isError, false);
    assert.deepEqual(result.structuredContent.items, [{ tenant_key: tenant, name: "Acceptance tenant" }]);
    assert.deepEqual(JSON.parse(result.content[0].text), result.structuredContent);
    const detail = await client.callTool({ name: "get_tenant", arguments: { tenant_key: tenant } });
    assert.equal(detail.structuredContent.tenant_key, tenant);
    const foreign = await client.callTool({ name: "get_tenant", arguments: { tenant_key: "MCPFIXTURE000002" } });
    assert.equal(foreign.isError, true);
    assert.equal(foreign.structuredContent.error.code, "tenant_not_found");
    // SDK 1.30 reports the HTTP error status without decoding the JSON-RPC body.
    await assert.rejects(
      client.callTool({ name: "list_tenants", arguments: { page_size: 51 } }),
      { code: 400 }
    );
    const invalid = await rpc(url, transport.sessionId, key, "tools/call", {
      name: "list_tenants", arguments: { page_size: 51 }
    });
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.error.code, -32602);
    assert.equal((await rpc(url, transport.sessionId, null)).status, 401);
    assert.equal((await rpc(url, transport.sessionId, "invalid-key")).status, 401);
    assert.equal((await rpc(url, transport.sessionId, "other-synthetic-key")).status, 404);
    const session = transport.sessionId;
    await transport.terminateSession();
    assert.equal((await rpc(url, session)).status, 404);
    await client.close();

    const revoked = await connect(url, "revocable-synthetic-key");
    await fixture.command({ action: "revoke" });
    assert.equal((await rpc(url, revoked.transport.sessionId, "revocable-synthetic-key")).status, 401);
    await revoked.client.close();
    await fixture.command({ action: "reset" });
    console.log(`PASS SDK ${mount}: tools, scope, arguments, authentication, revocation, DELETE`);
  }
  await officialScenarios(path.join(harness, "dist/index.js"), fixture.addresses.gateway);

  const retained = await connect(fixture.addresses.gateway);
  const previousSession = retained.transport.sessionId;
  await retained.client.close();
  const port = Number(new URL(fixture.addresses.gateway).port);
  await fixture.stop();
  const restarted = await startFixture(port, 1);
  const url = restarted.addresses.gateway;
  assert.equal((await rpc(url, previousSession)).status, 404);
  const expiring = await connect(url);
  const expiredSession = expiring.transport.sessionId;
  assert.deepEqual(await restarted.command({ action: "await_expiry", session: expiredSession }), { expired: true });
  assert.equal((await rpc(url, expiredSession)).status, 404);
  await expiring.client.close();
  const fresh = await connect(url);
  assert.equal((await fresh.client.callTool({ name: "list_tenants", arguments: {} })).isError, false);
  await fresh.transport.terminateSession();
  await fresh.client.close();
  await restarted.stop();
  console.log("PASS whole-BEAM restart, accelerated idle expiry, fresh-session recovery");
} finally {
  await Promise.allSettled([...clients].map(client => deadline(client.close(), "SDK cleanup", 5_000)));
  proxy?.closeAllConnections();
  proxy?.close();
  await Promise.all([...fixtures].map(async child => {
    if (child.exitCode !== null || child.signalCode !== null) return;
    const exited = once(child, "exit");
    child.kill("SIGKILL");
    await deadline(exited, "Fixture cleanup", 5_000);
  }));
  await rm(temporary, { recursive: true, force: true });
}
