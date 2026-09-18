# Get started with Elixir

Run Vxpipe from source to try a voice agent, then explore its components for your
own Elixir application. The repository is
[`HashNuke/vxpipe`](https://github.com/HashNuke/vxpipe).

## Requirements

- Elixir 1.19 / Erlang/OTP 28.
- PostgreSQL running locally.
- Node.js 24 and npm for the browser Console.
- Rust, C/C++ build tools, `pkg-config`, and OpenSSL development headers.
- Gemini and Deepgram API keys for the voice demo.

Docker, Tailscale, and the development reloader are not required for
this local demo. For a run without provider keys, see the
[local fixture instructions](development.md#local-fixtures).

## Run the voice demo

Clone the source and install its dependencies:

```shell
git clone https://github.com/HashNuke/vxpipe.git
cd vxpipe
mix deps.get
mix assets.setup
```

Initialize the local database:

```shell
mix ecto.create
mix ecto.migrate
```

Use the visible [`env.sample`](../env.sample) to configure the encryption keyring in your
launching shell. Follow [provider credential setup](provider-credential-storage.md#configure-and-provision)
to bootstrap a tenant and provision its Google and Deepgram `default` bindings. Provider
secrets are stored encrypted in PostgreSQL and are supplied to those commands through
protected stdin.

Select that tenant and start Vxpipe:

```shell
export VXPIPE_DEV_TENANT="TENANT_KEY"
APP_HOST=localhost VXPIPE_DEV_TLS=http mix run --no-halt
```

Direct Mix commands do not load `.env`. Development uses `vxpipe_dev` on localhost by
default; set `VXPIPE_DB_URL` to connect to a different database. The sample keeps
its call-scoped API key on the server and reuses your tenant after a restart.

Open [the voice console](http://localhost:4000/samples/pipecat-console), select
**Create room**, then **Connect**, and allow microphone access. You can speak or
type to the agent. Try:

- “What time is it?” to exercise a tool call and hear the answer.
- “Transfer me to billing” to switch to the sample billing agent.

Use `Ctrl+C` to stop the server. If the Erlang break menu appears, enter `a` to
abort the process.

## Use components in your Elixir application

Vxpipe's components can also serve as libraries within your own Elixir app.
Start with the component that matches your use case:

| Component | Use it for | Reference |
| --- | --- | --- |
| `vxpipe_call_engine` | Agent conversations, tools, and call lifecycles | [Call Engine](../apps/vxpipe_call_engine/README.md) |
| `vxpipe_gateway` | HTTP and WebRTC connections, including mounting routes in your app | [Gateway](../apps/vxpipe_gateway/README.md) |
| `vxpipe_agent_runtime` | Streamed model responses and tool execution | [Agent Runtime](reqllm-agent-runtime.md) |
| `vxpipe_mcp` | Connecting to remote MCP tools | [MCP client](mcp-client-conformance.md) |

The current checkout is an umbrella project. Independent dependency installation
and a complete consuming-host example are still part of the
[delivery milestone](milestones/embedded-and-container-delivery.md). Until those
are verified, use the checkout for the runnable demo and the references above to
explore the library APIs.

## Next steps

- [Sample walkthroughs](../apps/vxpipe_console/assets/README.md) cover tools, human transfers, and diagnostics.
- [Tenants and call definitions](tenant-control-plane.md) covers persistent storage and your own call definitions.
- [Development guide](development.md) covers reloading, HTTPS, fixtures, and working on Vxpipe itself.
