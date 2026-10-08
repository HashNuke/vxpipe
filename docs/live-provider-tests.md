# Opt-in live provider tests

Status: telephony and AI live modules use Mix tags, with `:live_providers`
excluded by default. Selected Gemini, Deepgram, OpenAI, DeepSeek, OpenRouter
and Fireworks protocol checks have passing evidence. The configured-service
live harness remains separate work; local encrypted service tests prove scoped
resolution and publication. Cartesia STT/TTS and ElevenLabs TTS have selected
passing live checks. ElevenLabs realtime STT has separately selected two-turn,
brief-first-answer and thirty-second initial-idle session evidence, plus local
scoped publication/startup and compiled room checks. Its separately selected
configured-service live room case also passes long-input recognition through an
encrypted platform service and the production reader; the earlier session tests
remain distinct evidence.
Hosted-agent STS is deferred outside the user-approved 2026-10-01 STT/TTS scope.

## Decision

Keep three test boundaries with different evidence:

| Boundary | Credential source | Runs by default | Proves |
| --- | --- | --- | --- |
| Local contract and service selection | Synthetic encrypted test records and fake transports | Yes, where existing suites allow it | Tenant credential precedence, platform inheritance, missing or unreadable tenant failure, authorization, and protocol decisions |
| Live provider protocol | A secret supplied to the test process | No | The actual provider accepts the adapter's wire format and returns the expected events |
| Live configured service | Dedicated test tenant and platform service records resolved through the production credential source | No | A call using the selected service reaches the real provider through the normal application path |

The second boundary belongs in the app that owns the provider adapter. It may
use an environment variable or secret manager as test input because it is
testing the provider protocol in isolation. It must not claim that tenant or
platform credential resolution was exercised. The third boundary must start
from a call spec or service binding and use
`Vxpipe.Calls.ProviderCredentialSource` or the corresponding telephony service
reader. It must not pass a raw test key directly to the provider adapter.
This preserves the umbrella's dependency direction: lower-level provider and
agent-runtime tests do not import Persistence just to test service selection.

The current service rule is exact provider/name selection: an existing tenant
credential wins; otherwise the platform credential is used. An inactive or
unreadable tenant credential fails closed and does not fall back. Local
[`ScopedProviderCredentialsTest`](../apps/vxpipe_persistence/test/vxpipe/persistence/scoped_provider_credentials_test.exs)
already proves these choices without paying for duplicate remote calls. A
live configured-service test should assert the resolved owner and credential
identity before its short provider operation. Run both sources against the
real provider only when a specific source-path integration risk warrants the
additional call.

## Selection and authorization

Use Mix/ExUnit's built-in tag filters. Every test that contacts a third-party
service gets `@moduletag :live_providers` and a provider tag such as
`@moduletag :live_openai`. Every child test helper excludes `:live_providers`
from ordinary `mix test`. Live modules do not carry `:integration`, so a broad
`--include integration` selection cannot include them. The Mix filter is the
explicit selection; no additional run flag is required.

Copy the [template](../config/live_providers.env.example) to
`~/.config/vxpipe/live_providers.env`, then replace the `todo` placeholders
only for the providers being run. URL placeholders include `https://`; the
runner treats unchanged placeholders as missing settings.
`bin/livetests run` loads that file for its child Mix process. It clears
ambient provider credentials first, so a dotenv hook on entering the directory
does not silently provide credentials. No arguments run every current live
provider test from the four owning directories (AgentRuntime, CallEngine,
Gateway and Console):

```shell
bin/livetests run
```

The runner forwards supplied arguments to `mix test`. For one provider or file:

```shell
bin/livetests run --only live_openai \
  apps/vxpipe_call_engine/test/integration/gpt_live_hosted_test.exs
```

The configured ElevenLabs STT room case belongs to Console, which composes
encrypted services, publication and room startup:

```shell
bin/livetests run --only live_elevenlabs \
  apps/vxpipe_console/test/integration/elevenlabs_configured_room_test.exs
```

Only that file's live case contacts the provider. Its local companion uses a
synthetic encrypted platform service and wire while retaining native acoustic
inference. The live case provisions an isolated encrypted platform service and
dedicated tenant, asserts the production reader's owner/identity/version, then
starts a published human room through normal attachment and PCM ingress. It
bounds one connection and 24.2 seconds of existing public input, with no retry.
No LLM, TTS or hosted-agent operation is needed for this STT acceptance case.
Explicit test shutdown is cleanup, not carrier hangup acceptance.

The explicit paths matter in an umbrella: `--only live_providers` against a
child with no matching tests exits with a no-tests result. From an owning child
directory, the same filters work without an umbrella path. When selected
without a required credential or fixture setting, the test should fail clearly
before contacting the provider. CI and the default suite do not select live
tags or load the credentials file.

Selected Deepgram tests use an Elixir helper in the Deepgram provider test
support. If the fixed PCM sample is absent, setup makes one Deepgram TTS
request for a short phrase. If the Opus sample is absent, it transcodes the PCM
locally with FFmpeg. Generated files remain in the Deepgram provider test
fixture directory for review and a separate commit; later runs reuse them.
The first run may therefore incur one additional billable TTS request. No
separate audio-path or expected-tail environment variables are needed. The
helper requests Deepgram's documented
[raw linear16 TTS output](https://developers.deepgram.com/docs/tts-media-output-settings)
at 16 kHz before local Opus transcoding.

Use a dedicated provider test project or account with an explicit spend limit
where the provider supports one. Supply keys through the shell environment or
a secret manager, never in a call spec fixture, committed file, command-line
argument, log, or test failure. OpenAI's
[production guidance](https://developers.openai.com/api/docs/guides/production-best-practices)
recommends environment variables or a secret manager instead of hard-coded
keys, and describes project spend limits. Each live test defines its maximum
sessions, input/audio duration, timeout, destination allowlist where relevant,
and retry policy. Record sanitized provider, model, credential scope, result,
and measured usage; do not retain raw authorization, audio, or transcripts.

### Telephony public endpoint

Telephony selections (`live_telephony`, `live_twilio`, `live_telnyx`, Twilio/Telnyx
test paths, or a full run) need a public HTTPS origin. `bin/livetests run` starts this
machine's `vxp-test-<machine>` Tailscale node with a port-443 Funnel to
`127.0.0.1:$TELEPHONY_TEST_PORT` (default 4600), exports `TELEPHONY_TEST_PUBLIC_URL`
and `TELEPHONY_TEST_PORT` to the child, and stops only what it started. One-time setup
and the reasons are in the [harness decision](live-telephony-harness.md).

```shell
bin/livetests tools:up       # keep the endpoint running across several runs
bin/livetests run --only live_telephony \
  apps/vxpipe_gateway/test/integration/public_telephony_endpoint_test.exs
bin/livetests tools:status
bin/livetests tools:down
```

The endpoint test starts the production gateway endpoint on the test port and requires
`/healthz` through the public URL. Setting `TELEPHONY_TEST_PUBLIC_URL` in the env file
uses that origin instead and leaves Tailscale alone.

Live tests register Elixir teardown that ends and verifies only their captured
Telnyx call-control IDs or Twilio call SIDs. This cleanup is independent of room
shutdown and performs no account sweep.

For recovery after an interrupted VM or an unknown dial outcome,
`bin/livetests telephony:hangup` ends
calls to or from this machine's provisioned test numbers on both configured
carriers. Use `telnyx:hangup` or `twilio:hangup` to select one provider. The optional
`--all-calls` flag includes unrelated calls across the configured accounts. Cleanup
does not need a running public endpoint and fails if calls remain or cannot be
verified; see [call cleanup](live-telephony-harness.md#call-cleanup).

## Configured-service fixture

For automated tests, provision a dedicated temporary tenant and the chosen
tenant or platform credential into the isolated test database through the
public administration path. A secret environment variable is only the input
to that encrypted provisioning step. The test then resolves and starts the
call through normal application readers. Use a distinct credential name and
test tenant, and clean up with the test sandbox. This is separate from the
provider-protocol test, which does not need a database.

Real carrier phone acceptance needs a reachable staging deployment, a
configured test number and application/webhook binding, and a person on the
phone. The configured service in that deployment is the source of truth;
the local Mix test database is not the deployment's credential store. The
manual observations stay in the milestone labnotes. Do not claim phone
interoperability from a direct WebSocket protocol test.

## Existing inventory and migration order

1. Add group and provider-specific live tags to current OpenAI, Deepgram,
   Gemini, Zenmux, Twilio, and Telnyx live modules, and exclude the group
   tag in every child test helper.
   Keep local HTTP, database, fake-socket, conformance, and loopback integration
   modules out of the live group. Keep `:integration` for local integration
   tests. Completed for the current inventory.
2. Verify ordinary `mix test` and `--include integration` exclude live modules.
   Verify `--only live_providers` and `--only live_<provider>` select the
   intended files. Verify missing secrets fail clearly after selection.
3. Add a test-only configured-service fixture at the Calls/Persistence
   boundary. Prove the fixture selects a tenant override and platform fallback
   with fake transports before any live use, then add one bounded real-provider
   call through a published test call spec.
4. Use the opt-in GPT-Live protocol lane and a configured Twilio or Telnyx
   phone leg for the remaining
   [GPT-Live milestone](milestones/gpt-live-speech-to-speech.md) acceptance.
   Record the six residual observations in
   [the duplex profile](sts-duplex-profile.md) and keep the milestone open
   until the authorized live and phone checks pass.

## Alternatives rejected

- Running all `:integration` tests for provider checks mixes local integration
  with billable calls and makes cost hard to see.
- An extra environment run gate duplicated Mix selection and made a selected
  test silently skip; the dedicated live tag is sufficient for opt-in.
- Passing environment keys straight to an end-to-end provider test bypasses
  the tenant/platform source contract that the test claims to verify.
- Forcing every low-level adapter test through a database would add an
  unrelated Persistence dependency and duplicate service-selection tests.
- Using the production tenant or platform database from `MIX_ENV=test` would
  make tests change live configuration and lose isolation.

## Initial tag migration evidence

Local `mix help test` documents `--include`, `--exclude`, and `--only`. With
`OPENAI_API_KEY` explicitly unset, both ordinary `mix test` and `--include
integration` excluded the two OpenAI tests. `--only live_openai` selected both;
they failed at `System.fetch_env!/1` before a provider connection. `--only
live_providers` selected the same two tests on that file and also stopped at
the missing-key check. At that migration checkpoint, the tags covered 14 live tests
across AgentRuntime (4), Artifacts (1, since retired), CallEngine (4), and Gateway (5). A child
without matching tags exits with no tests under `--only`; this is why the
umbrella command names the owning paths. The configured-service fixture and
authorized live runs were still pending. Formatting, warnings-as-errors compilation,
strict Credo, and the unused-dependency check passed. The first umbrella run
had three timing failures in unchanged tests; each passed in a focused rerun.
A repeat root `mix test --max-cases 2` passed all 2,868 tests with zero failures.


## Reviewed model catalog and current acceptance

`Vxpipe.Providers.LiveModels` in provider test support owns fixed model selections;
model overrides are not additional environment variables. Current direct LLM
checks use `gpt-6-luna` (OpenAI Responses), `deepseek-flash` (thinking disabled),
`google/gemini-3.5-flash-lite` (OpenRouter), and
`accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b` (Fireworks).
Each shared check makes at most two inference requests, capped at 256 output
tokens each: a streamed tool call and a continuation. It verifies parsed tool
arguments, nonempty final text and provider-reported usage. No automatic retries
are added. The chosen Fireworks Gemma listings require dedicated deployment;
the fixed Nemotron model is serverless and inexpensive.

```shell
bin/livetests run --only live_deepseek apps/vxpipe_agent_runtime/test/integration/deepseek_llm_test.exs
bin/livetests run --only live_openrouter apps/vxpipe_agent_runtime/test/integration/openrouter_llm_test.exs
bin/livetests run --only live_fireworks apps/vxpipe_agent_runtime/test/integration/fireworks_llm_test.exs
bin/livetests run --only live_openai apps/vxpipe_agent_runtime/test/integration/openai_llm_test.exs
```

Run one selected group at a time for this milestone. Deepgram samples include
two seconds of trailing silence for automatic turn completion and are reused;
no extra TTS call is needed when both fixture files exist. OpenAI hosted speech
checks cover reseeding/mute/talkover and delegated-tool continuation separately.
Results and earlier failures are recorded in
[checkpoint labnotes](../labnotes/20260930-0353-provider-expansion-gateway.md).
These direct protocol calls do not claim encrypted-service live-call acceptance.

Cartesia's selected TTS check uses `sonic-3.6` and the documented Skylar voice
from the shared test model catalog. It sends one short phrase with retries and
redirects disabled, acknowledges raw PCM credit, and requires generation and
playback settlement within bounded observation. It passed on 2026-09-30.
Platform/tenant credential inheritance, override and published startup are
verified separately with synthetic encrypted fixtures. The selected STT check
uses `ink-2` and reuses the committed public 16 kHz PCM sample, adding paced
silence within a ten-second input budget. It opens one connection, verifies
semantic turns and the final word, then requires close-and-drain completion.
It never generates another provider's sample. Both Cartesia checks passed on
2026-09-30.

```shell
bin/livetests run --only live_cartesia apps/vxpipe_call_engine/test/integration/cartesia_text_to_speech_test.exs
bin/livetests run --only live_cartesia apps/vxpipe_call_engine/test/integration/cartesia_speech_to_text_test.exs
```

Run these commands individually. See [TTS evidence](../labnotes/20260930-0705-cartesia-request-tts.md)
and [STT evidence](../labnotes/20260930-0753-cartesia-turn-stt.md).

ElevenLabs TTS uses `eleven_flash_v2_5`, the documented stock George voice
(`JBFqnCBsd6RMkjVDRZzb`) and 16 kHz raw PCM from the shared test catalog.
Its selected test sends exactly one short phrase, disables retries and redirects,
acknowledges PCM credit, and bounds generated audio to ten seconds with a
30-second observation deadline. It requires locally measured character/audio
usage and generation settlement; no audible output device is attached and it
does not claim the audio was heard. One test passed on 2026-09-30. Local encrypted
service checks separately prove platform inheritance, tenant override, private
credential redaction and published compiled startup. Saving the service does
not run or claim an authentication-only probe.

```shell
bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_text_to_speech_test.exs
```

See [ElevenLabs TTS evidence](../labnotes/20260930-0911-elevenlabs-request-tts.md).

### ElevenLabs Scribe protocol

The controlled manual assembly case is also independently selectable:

```shell
bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_controlled_segments_test.exs
```

It submits 23.6 seconds of the existing repeated public fixture, bounded to
25 seconds, and settles two manual segments on one connection. One run passes
in 24.9 seconds, seed 512880, preserving one cumulative turn end. The boundary
is supplied by the test; acoustic detection and conversational room acceptance
remain pending. No other paid case is included. See
[controlled segment evidence](../labnotes/20261001-0125-scribe-controlled-segments.md).

The long VAD experiment is independently selectable:

```shell
bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_long_vad_test.exs
```

It reuses the public fixture, repeats only its speech portion, and submits at
most 45 seconds of PCM on one connection without a manual commit. One selected
run passes (44.0 seconds, seed 364893): a segment arrives during the repeated
speech phase at 36 seconds of accepted client audio and another during silence
at 43.04 seconds. These are receipt positions, not provider processing cursors
or commit reasons. This protocol experiment does not establish natural-speech
quality or admit segment commits as room turn ends. See
[long VAD evidence](../labnotes/20261001-0102-scribe-long-vad.md). Do not repeat
the paid experiment merely to verify unrelated changes.

The preparation test uses fixed `scribe_v2_realtime`, 16 kHz PCM and the existing
public Deepgram sample with one second of additional silence (5.16 seconds
total). It opens one connection, paces bounded chunks, explicitly commits and
checks the known final word. Select the manual case independently of TTS and VAD:

```shell
bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_protocol_test.exs:12
```

One selected run passes. This verifies transcription protocol only; speech-start,
turn-end, room admission and scoped STT support are pending. The private key is
loaded by the existing runner. Ordinary `mix test` excludes this test. See
[protocol evidence](../labnotes/20260930-1042-elevenlabs-turn-contracts.md).
Conversational realtime STT has no accepted live case yet; hosted-agent STS is deferred.

The separate VAD case requests `commit_strategy=vad`, sends the existing fixture
with two seconds of paced silence, and checks automatic segment finalization
without sending a manual commit. It submits under ten seconds of audio through
one connection. The request fixes a 1.5-second silence threshold, 0.4 detection
threshold and 100 ms minimum speech/silence durations. Conflicting echoed settings
reject readiness; no model/detection-setting environment variables are required.
One selected run passes on 2026-10-01: one test, zero failures, one excluded,
6.6 seconds, seed 205077. An earlier attempt stopped at local database setup
before provider contact; setting `PGHOST` to the local socket directory uses the
documented peer-authenticated PostgreSQL connection. Mix TCP and DNS now work. Select only
this case; do not repeat the passing manual probe:

```shell
bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_protocol_test.exs:45
```

Even a passing short VAD case would not prove long-input turn boundaries,
speech-start notification, finite-input drain or conversational room support.
See [native VAD assessment](elevenlabs-turn-ownership.md#realtime-scope-and-native-vad-first).

### Historical ElevenLabs hosted-agent protocol

Hosted-agent STS is deferred by the 2026-10-01 scope decision. These previously
committed probes are historical research, not current acceptance requirements.
They remain excluded from ordinary tests and are explicitly skipped even when
`live_elevenlabs` or `live_providers` is selected. Current provider acceptance
executes STT/TTS cases; the historical file makes no hosted request.

The skipped preparation file records three cases: public model
metadata, create/read/sign/delete configuration validation without a speech
connection, and one native hosted conversation. The conversation uses fixed
Gemini 3.5 Flash Lite, minimal reasoning, a 128-token cap, V4 Turbo/George and
16 kHz PCM. It reuses the public fixture, paces at most ten seconds of input
including silence, requests one short response and requires explicit whole-response
completion. Backup LLMs and speculative generation are disabled. The agent waits
30 seconds before an idle prompt; the test closes its socket before deleting the
temporary agent. Every owned agent deletion requires HTTP 204, including callback failure.

One bounded historical conversation passes on 2026-09-30. Model metadata
and saved configuration pass independently. This proves native protocol only;
room/tool/history integration and production provisioning ownership remain open.
Temporary agent deletion is not deletion of hosted conversation records. See
[checkpoint evidence](../labnotes/20260930-1120-elevenlabs-agent-protocol.md).

The later uncommitted tool-resource case and implementation were removed after
the scope change. Its investigation and successful cleanup evidence remain in
[historical labnotes](../labnotes/20260930-2305-elevenlabs-tool-resources.md).

Cloudflare/Vercel gateway implementation is deferred. There is no current
`live_cloudflare` lane or gateway provider catalog entry. See the separate
[AI gateway routing design milestone](milestones/ai-gateway-routing.md).
