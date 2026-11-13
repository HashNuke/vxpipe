---
title: Adding providers and integrations
description: Extend installed capabilities and publish public integration definitions.
sidebar:
  order: 7
---

There are two extension paths. A native provider adds executable capability
adapters to Vxpipe. An integration directory entry supplies public setup metadata
for an installed provider or a compatible remote MCP. A JSON listing cannot
install code or grant access to an external account.

## Native provider ownership

[`Vxpipe.Providers.Registry`](../../../apps/vxpipe_providers/lib/vxpipe/providers/registry.ex)
maps exact provider IDs to fixed manifests. A manifest declares capability modules
and credential/validation metadata. Resolution also checks that the implementation
application is installed. Never turn an external provider string into an atom or
arbitrary module name.

Keep manifests/schemas in `vxpipe_providers`, speech implementations in Call
Engine, carrier protocols in Gateway, and model-loop behavior in Agent Runtime.
Add dependencies to the child that directly owns their use. Console presents the
declared credential form/catalog; it does not implement a second credential store.

Implement the narrow capability, then expose it in the manifest/catalog only when
its actual acceptance scope permits. An experimental adapter file is not a
production-selectable feature. Read the installed manifest instead of maintaining
a second evergreen provider-support table in prose.

## Configured-service authority

The saved call spec selects the provider, model, voice and public options. Private
startup resolves its named tenant or inherited platform credential from the
configured database credential source. Removing or revoking that credential still
blocks startup. The installed provider registry maps IDs to executable drivers;
it does not enable services for a tenant.

STT, TTS and STS do not read application-configured provider lists or `enabled`
flags. Development and production use the same startup path. Keeping a second
release-level enablement list was rejected because a service configured through
the UI could otherwise validate successfully and fail only when a call started.
The old development call spec embedded in configuration is also retired; use
`examples/call-specs/` and save/publish the chosen spec in the database.

`SpeechRuntimeOptions` owns bounded transport defaults (STT ingress and TTS request
limits). Tests can pass `speech_runtime` explicitly to inject local transports;
this is a trusted internal startup option, not call-spec data or service
configuration. Legacy test fixtures are captured by the test startup helper only.
These overrides cannot replace the selected provider/model or credential source.

The separately hosted Morse API still has a private deployment-origin setting,
`MORSE_CODE_API_BASE_URL`, shared by discovery and speech transport. This is live
endpoint wiring, not a provider/model selection or enablement gate; it remains
outside this cleanup. Hosted speech adapters use their implemented protocol
endpoints.

Regression coverage exercises database-backed ElevenLabs STT, TTS and STS with no
host registration, tenant-over-platform precedence and credential deletion. Room
startup also runs with poisoned obsolete application speech settings to verify
that neither startup stage reads them.

## Speech adapter checklist

1. Implement `Speech.STTProvider`, `TTSProvider` or `STSProvider` as appropriate.
   Use the [semantic runtime contracts](speech-runtime.md); STS is not independent
   STT plus TTS when the provider owns the model conversation.
2. Implement pure `models/0` and `configure/1`. Return validated public settings,
   exact directional formats, readiness, usage provenance and supported semantic
   evidence. Declare exactly one recommended model.
3. Describe voices as absent, a known list or a free-text selection, including
   the actual option name. Keep public model/voice selection distinct from wire
   naming; the adapter composes the provider's concrete ID.
4. Resolve credentials only in private startup. Use allocation-local supervision
   for providers and request workers. Bind the event channel before blocking I/O
   and honor the absolute startup/command deadline.
5. Implement bounded input, exact output credit, cancellation and terminal evidence.
   `:busy` means an input chunk was not accepted. Do not return success for an
   unbounded mailbox enqueue.
6. Run the common conformance harness, actual local protocol fixture and selected
   live/configured-service lane before expanding production support.

The [compiled TTS example](../../../apps/vxpipe_call_engine/test/support/speech_guide_tts_provider.ex)
is a small complete implementation. The behavior modules and shared conformance
tests are executable references; avoid copying a provider-specific socket API
into the common session contract.

TTS allocations retain the provider's native PCM format for credit and usage.
The TTS capability converts audio to 48 kHz mono PCM at the playout boundary,
matching STS and gateway output. Track cumulative input samples across chunks;
normalization must preserve duration and must not inflate provider usage.

For conversational STT, declare the actual endpoint authority. For finite agent
output recognition, implement explicit `finish_input`/`input_finished` proof.
For STS, declare who controls responses, transcript settlement, interruption,
duplex, restoration and tool-result continuation. Unsupported operations reject
explicitly; a provider name alone does not guarantee those capabilities.

## Provider protocol details

Keep wire differences local: request envelopes, auth headers, model naming,
provider turn IDs, continuation messages and resumption handles. The common
runtime still owns permission intervals, selected tools and effect execution.
Examples include persistent Deepgram streams, Scribe segment/gap assembly,
Google session resumption and GPT-Live's delegated response envelopes.

Do not change upstream API/model families merely to make a fixture pass. Verify
against the selected adapter's current official protocol and record limits on
hosted evidence. Progress deadlines should detect stalled work, not impose an
arbitrary duration cap on speech that continues making valid progress.

LLM integrations validate portable generation options and provider-native routing
options. Reject unknown or authentication/transport overrides. A router's selected
upstream is part of its configured policy; Vxpipe must not silently choose a new
recipient for retries or context compaction.

Carrier adapters translate dialing, answer, status, media and termination into
Gateway's common lifecycle. Authenticate raw callbacks before trusting routing;
retain initialized service/credential identity for active legs. Test both dial
directions, uncertain submission, duplicate callbacks and selective hangup.

### Telnyx v2 billing events

Telnyx uses the v2 `data.record_type/event_type/id/occurred_at/payload` envelope and
ED25519 verification of the timestamp plus raw request body. The test provisioner
sets and repairs both `webhook_api_version: "2"` and `call_cost_in_webhooks: true`.
See [webhook format](https://developers.telnyx.com/docs/voice/programmable-voice/voice-api-webhooks),
[application settings](https://developers.telnyx.com/api-reference/call-control-applications/update-a-call-control-application),
and the `CallCost` schema in the [official OpenAPI specification](https://github.com/team-telnyx/openapi/blob/master/openapi/spec3.json).

`call.cost` is a billing event, separate from call lifecycle dispatch. Gateway
finds the persisted telephony usage by provider leg and session, then checks the
application against the immutable call plan. The tenant URL must match the stored
tenant; the platform URL can receive either scope. The original credential identity
supplies the current verification key. Authentication precedes every write.
An index supports this lookup without scanning all calls. Missing or ambiguous
usage, deleted credentials and storage failures return 503 for carrier retry.
Changing current number routing cannot reassign the charge to another tenant.

The existing immutable usage store records final cumulative decimal costs, billed
milliseconds and component costs included in the total. Total currency comes from
agreeing component currencies; no currency is guessed. A stable event receipt and
per-component observation identities make retries idempotent and reject a changed
payload under the same event ID. A partial write can resume on retry; publication
is requested after the full event has been stored. Error events store an unknown
measurement, not zero, and never change the call's lifecycle outcome.

This reuses durable call plans and usage instead of retaining live call processes
or adding a second billing queue/store. It relies on the carrier's retry window
when usage has not yet reached persistence; it does not backfill historical events
that Telnyx never delivered. Focused mounted HTTP tests cover signed v2 payloads,
scope and amount validation; persistence tests cover ended calls, immutable replay
and ambiguous targets. Provisioning fixtures mock the carrier API; no paid calls
are needed for these checks.

## Public directory definitions

Canonical definitions are top-level `integrations/*.json` in this repository.
Follow the [contribution guide](../../../integrations/README.md) and its schema.
Use stable filenames/IDs, official endpoint/setup sources and real declared icons.
Definitions contain no tenant data, shared secret or OAuth grant.

```shell
python3 -m pip install -r integrations/requirements-dev.txt
python3 integrations/scripts/validate.py
python3 -m unittest discover -s integrations/tests
```

The sibling `../vxpipe-integrations-web` repository owns the publisher/API. Its
signed GitHub push webhook imports top-level definitions from one pinned commit
of `HashNuke/vxpipe` `main`. Data changes refresh the catalog without rebuilding
the publisher. Failed imports retain the last published snapshot. There is no
runtime source fallback to the retired standalone definitions repository.

## Directory API and Console consumption

Console fetches the public directory server-side and joins its pages with a
separate complete local connection-status projection. It sends the immutable
installation release version in `X-VxPipe-Version`, never tenant IDs, grants or
local connection state. Directory origin is host configuration.

The v1 envelope identifies `schema_version`, permanent `directory_id`, opaque
`revision`, `resource`, version echo, items and authoritative pagination. Integration
pages also echo category/query/scope. Cursors belong to that request and snapshot;
they are not page numbers. Do not merge a failed remote page with unrelated local
rows or infer totals from its visible length.

Unknown installation versions, invalid envelopes or unavailable service trigger
the installed native-provider fallback. A valid empty result remains empty.
Expired cursors restart paging; missing categories are distinct from outages.
Directory metadata cannot add an executable provider, platform MCP inheritance
or authorization method unsupported by the installed client.

Reference downloads:

- [Response schema](../../assets/integrations/integrations-directory.schema.json)
- [Integration page](../../assets/integrations/integrations-directory.example.json)
- [Category page](../../assets/integrations/integrations-directory.categories.example.json)
- [Search page](../../assets/integrations/integrations-directory.search.example.json)

The schema is also used by the Console validator. These examples describe the
public listing protocol, not the tenant tool-catalog cache. That separate cache
is covered in [Agent runtime and MCP](agents-and-mcp.md#tenant-catalog-cache).
