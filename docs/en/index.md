---
title: Getting started
description: Self-hostable voice agent platform.
sidebar:
  order: 1
---

The runnable installation today is a source checkout. Packaged
[Docker](usage/install/docker.md) and [Railway](usage/install/railway.md) delivery is planned.
For a first browser call, have a Deepgram key for speech and either a Google AI
Studio or Zenmux key for the language model. Telephony and MCP servers are optional.

## Start Vxpipe

Install the [development prerequisites](development/local-development.md), then:

```shell
git clone https://github.com/HashNuke/vxpipe.git
cd vxpipe
bin/setup
bin/dev
```

Setup prepares dependencies, assets, local secrets and isolated databases, then
prints your Console URL. Open that URL and complete first-account setup. Use the
printed local origin as the Installation URL. Public deployments need HTTPS.

## Connect services and load a sample

Open **Getting started**. The Console prepares its demo tenant; retries reuse
that tenant even if you later rename it. Connect Deepgram and a language-model
provider through **Services**. Test credentials where offered, then save them.
A successful credential test alone does not save a connection.

Load a voice-conversation sample call spec. The sample catalog also includes
agent handoff and human handoff examples. Samples are ordinary saved call specs:
you can inspect and edit them. Reinstalling does not overwrite a sample you have
changed; resolve the reported conflict instead.

The editor saves and publishes definitions; it does not itself start a test call.
Use the development playground below for the first voice exchange.

## Run the development playground

The managed playground is also available when `VXPIPE_DEV_TENANT` selects a tenant
with saved Google and Deepgram credentials named `default`. Console-created
provider bindings normally use the provider name, so provision the playground's
explicit default bindings from a terminal at the repository root:

```shell
set -a
. ./.env
set +a
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider google < protected-google-credential.json
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider deepgram < protected-deepgram-credential.json
```

Use the tenant key from its Console URL. Each protected input file contains
`{"api_key":"REPLACE_WITH_PROVIDER_KEY"}` with that provider's real key; keep the
files outside source control. Provision only missing default bindings; the
command does not silently replace an existing one. Set `VXPIPE_DEV_TENANT` to
that tenant key in the checkout's ignored `.env` and restart `bin/dev`.

After logging in, open `/admin/samples/pipecat-console`, choose **Create room**,
then **Connect**. Ask “What time is it?” to exercise a platform tool, or “Transfer
me to billing” to try the sample agent handoff. Verify a spoken exchange and its
transcript: text alone does not prove microphone input or audible playback.
Stop the call when finished.

For a credential-free development check, use the local Morse fixture lane in
[Development workflow](development/local-development.md#local-fixtures).

## Build your receptionist

1. Read [Core concepts](usage/concepts.md), then create your own
   [call spec](usage/call-specs.md) with the receptionist prompt and supported model/voice.
2. Add [tools and tenant MCP connections](usage/agents-and-tools.md), granting only the
   tools that conversation should use.
3. Configure [telephony](usage/telephony.md), including a saved carrier service and a
   published incoming route.
4. Test real caller audio, a tool invocation, transfer success/failure and hangup.
   Inspect the resulting call before accepting unattended traffic.
