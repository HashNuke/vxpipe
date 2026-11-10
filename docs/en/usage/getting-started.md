---
title: Getting started
description: Start from a source checkout, connect services and try your first voice call.
sidebar:
  order: 1
---

The runnable installation today is a source checkout. Packaged
[Docker](install/docker.md) and [Railway](install/railway.md) delivery is planned.
For a first browser call, have a Deepgram key for speech and either a Google AI
Studio or Zenmux key for the language model. Telephony and MCP servers are optional.

## Start Vxpipe

Install the [development prerequisites](../development/local-development.md), then:

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

Open the sample's call/debug interface and allow microphone access. Complete one
spoken exchange and inspect its transcript. A model's text reply alone does not
verify microphone input or audible playback.

## Explicit development playground

The managed playground is also available when `VXPIPE_DEV_TENANT` selects a tenant
with saved Google and Deepgram credentials named `default`. Set that tenant key
in the checkout's ignored `.env` and restart `bin/dev`.

After logging in, open `/admin/samples/pipecat-console`, choose **Create room**,
then **Connect**. Ask “What time is it?” to exercise a platform tool, or “Transfer
me to billing” to try the sample agent handoff. Stop the call when finished.

For a credential-free development check, use the local Morse fixture lane in
[Development workflow](../development/local-development.md#local-fixtures).

## Build your receptionist

1. Read [Core concepts](concepts.md), then create your own
   [call spec](call-specs.md) with the receptionist prompt and supported model/voice.
2. Add [tools and tenant MCP connections](agents-and-tools.md), granting only the
   tools that conversation should use.
3. Configure [telephony](telephony.md), including a saved carrier service and a
   published incoming route.
4. Test real caller audio, a tool invocation, transfer success/failure and hangup.
   Inspect the resulting call before accepting unattended traffic.
