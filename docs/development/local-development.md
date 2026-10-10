# Local development

Here's how to get Vxpipe running on your machine. You can start the Console
without provider credentials and use local fixtures while developing.
For a first provider-backed voice call, follow
[Get started with Elixir](../getting-started-elixir.md).

## Prerequisites

You'll need these tools:

- Elixir 1.19 and Erlang/OTP 28.
- Node.js and npm, using the version in [`.tool-versions`](../../.tool-versions).
- Python 3.10+ and Git.
- PostgreSQL, running locally.
- Rust, C/C++ build tools, `pkg-config` and OpenSSL development headers.

## Get a checkout

Clone the repository and step into its directory:

```shell
git clone https://github.com/HashNuke/vxpipe.git
cd vxpipe
```

If you use asdf or mise, you can install the versions pinned in
[`.tool-versions`](../../.tool-versions) from this directory. Choose the command
for your version manager.

With [asdf](https://asdf-vm.com/manage/configuration.html#tool-versions), with
the Erlang, Elixir, Node.js and Python plugins installed:

```shell
asdf install
```

With [mise](https://mise.jdx.dev/cli/install.html):

```shell
mise install
```

## Initialize a checkout

Now prepare your checkout:

```shell
bin/setup
```

Setup installs project dependencies, builds frontend assets, prepares local
configuration and migrates the development and test databases. It prints the
assigned Console URL.

Run setup separately in each checkout. See
[worktree isolation](worktree-isolation.md) for how Vxpipe keeps their state separate.

## Start the development stack

Start the Console:

```shell
bin/dev
```

Open the Console `/admin` URL printed by setup. The launcher loads the checkout's
`.env` and starts the umbrella applications together. Frontend assets rebuild
while it runs; restart the launcher after backend or runtime configuration changes.

For component development, run `npm run storybook` in another terminal.

The server starts without provider credentials. To use the browser voice sample,
follow [provider credential setup](../provider-credential-storage.md#configure-and-provision)
and select the provisioned tenant as described in the
[first-call guide](../getting-started-elixir.md#run-the-voice-demo).

## Local fixtures

The fixture model and Morse speech providers let you exercise calls without
external providers. Run their voice round trip from the owning application:

```shell
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
```

See the [local Morse provider documentation](../../apps/vxpipe_call_engine/README.md#local-morse-audio-providers)
for the supported audio and fixture behavior. The browser sample uses its
configured providers; it does not automatically select these fixtures.

## HTTPS development

With Tailscale and `jq` installed and HTTPS enabled on your tailnet, run:

```shell
bin/dev --tailscale
```

This serves the Console on the machine's Tailscale address. The
[HTTPS launcher](../../bin/with-tailscale) owns hostname discovery and certificates.
For carrier ingress and live-call testing, see the
[live telephony harness](live-telephony-harness.md).

## Where to look next

- [Setup command](../../bin/setup) and [development launcher](../../bin/dev): checkout preparation and startup.
- [Platform settings](../../env.sample) and [runtime configuration](../../config/runtime.exs): local configuration and how it is consumed.
- [Tenant operations](../tenant-control-plane.md): tenant keys and call-spec publication.
- [Console walkthroughs](../../apps/vxpipe_console/assets/README.md): browser samples, tools and human transfers.
- [Development documentation](../README.md#development): testing, verification and frontend topics.
