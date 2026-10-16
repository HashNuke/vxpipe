// Opt-in wire acceptance. All credentials and tenant records are synthetic.
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawn, execFileSync } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";
import { allTools, callTools, tenantTools, exerciseProducts } from "./product_scenarios.mjs";

const version = "2025-11-25";
assert.equal(process.argv.length, 2, "Usage: bin/test-platform-mcp");
let key;
const cache = execFileSync("npm", ["config", "get", "cache"], { encoding: "utf8" }).trim();
const fixtures = new Set();
const clients = new Set();
const temporary = await mkdtemp(path.join(os.tmpdir(), "vxpipe-platform-mcp-"));
let proxy;
let stage = "dependency discovery";

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
  let failureStage = "startup";
  let pending;
  const ready = new Promise((resolve, reject) => { pending = { resolve, reject }; });
  const lines = createInterface({ input: child.stdout });
  const errors = createInterface({ input: child.stderr });
  errors.on("line", line => {
    if (/^PLATFORM_MCP_FAILURE [a-z]+$/.test(line)) failureStage = line.slice(21);
  });
  lines.on("line", line => {
    if (line.startsWith("PLATFORM_MCP ")) {
      const result = JSON.parse(line.slice(13));
      const waiter = pending;
      pending = undefined;
      waiter?.resolve(result);
    }
  });
  child.on("error", error => pending?.reject(error));
  child.on("exit", code => {
    if (pending) console.error(`FAIL fixture ${failureStage} (exit ${code})`);
    pending?.reject(new Error("Fixture exited"));
  });
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
  Object.assign(fixture, await deadline(ready, "Fixture startup"));
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

async function tokenRequest(url, params) {
  const response = await fetch(new URL("/oauth/token", url), {
    method: "POST", body: new URLSearchParams(params), signal: AbortSignal.timeout(10_000)
  });
  assert.equal(response.status, 200, "OAuth token exchange");
  const tokens = await response.json();
  assert.ok(tokens.access_token && tokens.refresh_token && tokens.expires_in > 0);
  return tokens;
}

async function exerciseOAuth(fixture, url, connect) {
  const endpoint = new URL(url);
  const resourceResponse = await fetch(new URL(`/.well-known/oauth-protected-resource${endpoint.pathname}`, url));
  assert.equal(resourceResponse.status, 200);
  const resource = await resourceResponse.json();
  assert.equal(resource.resource, url);
  assert.deepEqual(resource.authorization_servers, [endpoint.origin]);
  const serverResponse = await fetch(new URL("/.well-known/oauth-authorization-server", url));
  assert.equal(serverResponse.status, 200);
  const server = await serverResponse.json();
  assert.equal(server.issuer, endpoint.origin);
  assert.deepEqual(server.code_challenge_methods_supported, ["S256"]);
  const redirect = "http://127.0.0.1:43210/callback";
  const registered = await fetch(server.registration_endpoint, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ client_name: "Official SDK acceptance", redirect_uris: [redirect] }),
    signal: AbortSignal.timeout(10_000)
  });
  assert.equal(registered.status, 201);
  const client = await registered.json();
  assert.ok(client.client_id && !client.client_secret);
  const verifier = randomBytes(32).toString("base64url");
  const params = { response_type: "code", client_id: client.client_id, redirect_uri: redirect,
    scope: "mcp", state: "sdk-pkce-state", resource: url, code_challenge_method: "S256",
    code_challenge: createHash("sha256").update(verifier).digest("base64url") };
  const approved = url === fixture.addresses.console
    ? await browserAuthorize(fixture, server.authorization_endpoint, params)
    : await fixture.command({ action: "authorize", params, resource: url });
  assert.equal(approved.state, params.state);
  const exchange = { grant_type: "authorization_code", client_id: client.client_id,
    redirect_uri: redirect, resource: url, code: approved.code, code_verifier: verifier };
  const invalid = await fetch(server.token_endpoint, {
    method: "POST", body: new URLSearchParams({ ...exchange, code_verifier: randomBytes(32).toString("base64url") }),
    signal: AbortSignal.timeout(10_000)
  });
  assert.equal(invalid.status, 400);
  const tokens = await tokenRequest(url, exchange);
  const connected = await connect(url, tokens.access_token);
  assert.equal((await connected.client.listTools()).tools.length, 17);
  await connected.transport.terminateSession();
  await connected.client.close();
}

async function browserAuthorize(fixture, authorizationUrl, params) {
  const cookies = new Map();
  const origin = new URL(authorizationUrl).origin;
  async function request(path, options = {}) {
    const target = new URL(path, origin);
    assert.equal(target.origin, origin, "Browser credentials stay on fixture origin");
    const response = await fetch(target, {
      ...options, redirect: "manual", signal: AbortSignal.timeout(10_000),
      headers: { cookie: [...cookies].map(([name, value]) => `${name}=${value}`).join("; "), ...options.headers }
    });
    for (const value of response.headers.getSetCookie()) {
      const pair = value.split(";", 1)[0];
      const equals = pair.indexOf("=");
      cookies.set(pair.slice(0, equals), pair.slice(equals + 1));
    }
    return response;
  }
  const initial = await request(`${authorizationUrl}?${new URLSearchParams(params)}`);
  assert.equal(initial.status, 302, "Start browser authorization");
  const resume = initial.headers.get("location");
  assert.match(resume, /^\/oauth\/authorize\/[A-Za-z0-9_-]{43}$/);
  const unauthenticated = await request(resume);
  assert.equal(unauthenticated.status, 302);
  assert.equal(unauthenticated.headers.get("location"), "/auth/login");
  const loginPage = await request("/auth/login");
  assert.equal(loginPage.status, 200);
  const loginCsrf = (await loginPage.text()).match(/name="csrf-token" content="([^"]+)"/)?.[1];
  assert.ok(loginCsrf);
  const login = await request("/auth/api/login", {
    method: "POST", headers: { "content-type": "application/json", "x-csrf-token": loginCsrf },
    body: JSON.stringify(fixture.browser_login)
  });
  assert.equal(login.status, 200, "Real browser login");
  const consent = await request(resume);
  assert.equal(consent.status, 200, "Resume browser consent after login");
  const html = await consent.text();
  assert.ok(html.includes("Official SDK acceptance") && html.includes(params.resource));
  const csrf = html.match(/name="_csrf_token" value="([^"]+)"/)?.[1];
  assert.ok(csrf);
  const decision = await request(resume, {
    // Native form submission under the consent page's no-referrer policy.
    method: "POST", headers: { origin: "null" },
    body: new URLSearchParams({ _csrf_token: csrf, decision: "approve" })
  });
  assert.equal(decision.status, 302, "Approve browser consent");
  const callback = new URL(decision.headers.get("location"));
  assert.equal(callback.origin + callback.pathname, params.redirect_uri);
  assert.equal(callback.searchParams.get("state"), params.state);
  assert.ok(callback.searchParams.get("code"));
  return Object.fromEntries(callback.searchParams);
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
    child.stdout.resume();
    child.stderr.resume();
    try {
      const [code] = await deadline(once(child, "exit"), scenario);
      assert.equal(code, 0, `${scenario} failed (private transcript omitted)`);
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
    const headers = { Authorization: `Bearer ${secret}` };
    const transport = new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers } });
    await deadline(client.connect(transport), "SDK initialization");
    assert.equal(transport.protocolVersion, version);
    assert.ok(transport.sessionId);
    return { client, transport, headers };
  }

  stage = "fixture startup";
  const fixture = await startFixture();
  for (const [mount, url] of Object.entries(fixture.addresses)) {
    const credentials = fixture.credentials[mount];
    key = credentials.platform.access_token;
    stage = `${mount} OAuth discovery and PKCE`;
    await exerciseOAuth(fixture, url, connect);
    stage = `${mount} initialization/catalog`;
    const { client, transport, headers } = await connect(url);
    const catalog = await client.listTools();
    assert.deepEqual(catalog.tools.map(tool => tool.name).sort(), allTools);
    await exerciseProducts(client, { tenant: fixture.tenant, mount, secrets: [...Object.values(fixture.keys), ...Object.values(credentials).flatMap(value => [value.access_token, value.refresh_token])], progress: name => { stage = `${mount} ${name}`; } });
    stage = `${mount} authority/schema/revocation`;

    for (const [kind, expected] of [["calls", callTools], ["full", tenantTools]]) {
      const scoped = await connect(url, credentials[kind].access_token);
      assert.deepEqual((await scoped.client.listTools()).tools.map(tool => tool.name).sort(), expected);
      const own = await scoped.client.callTool({ name: "list_tenants", arguments: {} });
      assert.ok(own.structuredContent.items.length === 1 && own.structuredContent.items[0].tenant_key === fixture.tenant);
      const foreign = await scoped.client.callTool({ name: "get_tenant", arguments: { tenant_key: fixture.foreign } });
      assert.ok(foreign.isError && foreign.structuredContent.error.code === "tenant_not_found");
      assert.equal((await rpc(url, scoped.transport.sessionId, credentials[kind].access_token, "tools/call", { name: "list_users", arguments: {} })).status, 403);
      await scoped.transport.terminateSession();
      await scoped.client.close();
    }
    await assert.rejects(client.callTool({ name: "list_tenants", arguments: { page_size: 51 } }), { code: 400 });
    for (const [name, arguments_] of [
      ["list_tenants", { page_size: 51 }],
      ["update_user", { user_id: "11111111-1111-4111-8111-111111111111", enabled: "true", password: "private-sdk-invalid-input" }],
      ["hangup_call", { tenant_key: fixture.tenant, call_id: "call", incarnation_id: "forged" }]
    ]) {
      const invalid = await rpc(url, transport.sessionId, key, "tools/call", { name, arguments: arguments_ });
      assert.equal(invalid.status, 400);
      assert.equal(invalid.body.error.code, -32602);
      assert.ok(!JSON.stringify(invalid.body).includes("private-sdk-invalid-input"));
    }
    assert.equal((await rpc(url, transport.sessionId, null)).status, 401);
    assert.equal((await rpc(url, transport.sessionId, "invalid-key")).status, 401);
    assert.equal((await rpc(url, transport.sessionId, credentials.other.access_token)).status, 404);
    assert.equal((await rpc(url, transport.sessionId, fixture.keys.platform)).status, 401);
    const product = await fetch(url.replace(/\/mcp$/, "/api/tenants"), {
      headers: { authorization: `Bearer ${fixture.keys.platform}` }, signal: AbortSignal.timeout(10_000)
    });
    assert.equal(product.status, 200, "Product HTTP API still accepts API keys");
    const foreignResource = Object.entries(fixture.credentials).find(([name]) => name !== mount)[1];
    assert.equal((await rpc(url, transport.sessionId, foreignResource.platform.access_token)).status, 401);
    const refreshed = await tokenRequest(url, {
      grant_type: "refresh_token", client_id: credentials.platform.client_id,
      refresh_token: credentials.platform.refresh_token, resource: url
    });
    key = refreshed.access_token;
    headers.Authorization = `Bearer ${key}`;
    assert.equal((await rpc(url, transport.sessionId)).status, 200);
    assert.ok((await client.listTools()).tools.length === 17);
    const session = transport.sessionId;
    await transport.terminateSession();
    assert.equal((await rpc(url, session)).status, 404);
    await client.close();

    const issued = await fixture.command({ action: "issue_revocable", resource: url });
    const revoked = await connect(url, issued.access_token);
    const revocation = await fetch(new URL("/oauth/revoke", url), {
      method: "POST", body: new URLSearchParams({ client_id: issued.client_id, token: issued.access_token }),
      signal: AbortSignal.timeout(10_000)
    });
    assert.equal(revocation.status, 200);
    assert.equal((await rpc(url, revoked.transport.sessionId, issued.access_token)).status, 401);
    await revoked.client.close();
    console.log(`PASS SDK ${mount}: all 17 tools, actual stores, authority catalogs, schema, redaction, refresh continuity, revocation, DELETE`);
  }
  stage = "official scenarios";
  key = fixture.credentials.gateway.platform.access_token;
  await officialScenarios(path.join(harness, "dist/index.js"), fixture.addresses.gateway);

  stage = "restart/expiry";
  const retained = await connect(fixture.addresses.gateway);
  const previousSession = retained.transport.sessionId;
  await retained.client.close();
  const port = Number(new URL(fixture.addresses.gateway).port);
  await fixture.stop();
  const restarted = await startFixture(port, 1);
  const url = restarted.addresses.gateway;
  key = restarted.credentials.gateway.platform.access_token;
  assert.deepEqual(await restarted.command({ action: "session_exists", session: previousSession }), { exists: false });
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
} catch {
  console.error(`FAIL ${stage}; private diagnostics omitted`);
  process.exitCode = 1;
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
