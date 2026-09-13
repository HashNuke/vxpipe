# Vxpipe

**Build voice agents that can talk, take action, and bring in the right person.**

Vxpipe is a platform for real-time voice applications, built with Elixir. Connect
agents to callers in the browser or over the phone, give them tools, and hand
conversations between agents and people.

- **Keep the conversation moving.** Stream spoken replies, handle interruptions,
  and keep talking while tools work in the background.
- **Connect agents to your business.** Use application tools and MCP servers to
  look things up and take action during a call.
- **Make the handoff.** Route callers to another agent or brief a person privately
  before bringing them into the conversation.
- **Understand each call.** Inspect call timelines, transcripts, latency, and
  usage, with optional recordings and saved call history.

Docker is the primary distribution target, with the image planned as
`vxpipe/vxpipe`. You can also use Vxpipe's components as libraries in your own
Elixir applications.

## Try the voice demo from source

Until the Docker image is available, you can run the demo from source.

You'll need Elixir 1.19 / Erlang/OTP 28, Node.js 24, Rust, and
[native build tools](docs/development.md#prerequisites), plus Gemini and Deepgram
API keys. The local demo runs without PostgreSQL.

Clone the repository and install the dependencies:

```shell
git clone https://github.com/HashNuke/vxpipe.git
cd vxpipe
mix deps.get
mix assets.setup
```

Set your provider keys and start the demo:

```shell
export GEMINI_API_KEY="your-gemini-api-key"
export DEEPGRAM_API_KEY="your-deepgram-api-key"
APP_HOST=localhost VXPIPE_DEV_TLS=http mix run --no-halt
```

Open [the voice console](http://localhost:4000/pipecat-console), select
**Create room**, then **Connect**, and allow microphone access. Ask
“What time is it?” to hear the agent use a tool and answer aloud. Try
“Transfer me to billing” to switch to the sample billing agent.

The sample uses Gemini for responses and Deepgram for speech. To explore without
provider keys, use the [local fixture demo](docs/development.md#local-fixtures),
which responds to typed input with preset text and Morse-code audio.

## Go further

- [Development guide](docs/development.md): setup, live reloading, HTTPS, and local fixtures.
- [Sample walkthroughs](apps/vxpipe_console/assets/README.md): tool calls, human transfers, and diagnostics.
- [Tenants and call definitions](docs/tenant-control-plane.md): configure your own calls and persistent storage.
- Elixir libraries: [Call Engine](apps/vxpipe_call_engine/README.md) and [Gateway](apps/vxpipe_gateway/README.md).
