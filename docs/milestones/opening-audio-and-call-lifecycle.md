# Opening audio and call lifecycle

Status: complete (2026-09-10). Specification review: approved (2026-09-08).
Prerequisites: [Prepared admission](prepared-call-admission.md); [Background tools](background-tool-conversation.md).
Sources: [Opening audio](../../labnotes/20260905-0405-call-definition-design.md#optional-opening-audio-before-entry-reception--approved-startup-decision); [greetings](../../labnotes/20260905-0405-call-definition-design.md#first-message-behavior--approved-g7-decision); [timers](../../labnotes/20260905-0405-call-definition-design.md#startup-idle-tool-waiting-and-duration--approved-r27r30).

## Runnable outcome

A caller hears optional configured opening audio before normal conversation. The agent then follows its greeting mode, can use current time/hangup tools, and respects readiness, idle, and whole-call duration rules.

## Specification

- Optional call-level opening_audio accepts a supported file URL or fixed text rendered with the initial receiving agent's resolved TTS service/voice. No LLM-generated notice, variable interpolation, arbitrary later agent, or implicit fallback voice. Cache by exact text/output settings/provider/model/voice and tenant/binding without secrets.
- Capabilities may warm up during opening playback but receive no participant audio until actual playout completion. Neither downloaded/enqueued audio nor provider readiness opens the gate. Do not record/replay blocked audio; incomplete playback cannot silently release it. Omission adds no opening delay.
- Resolve the still-unspecified source wire/format, fetch/cache and transport-completion details before implementation; document safe supported behavior. If text has no initial agent/TTS, fail explicitly rather than inventing one. Playback failure/text barge-in behavior needs a narrow explicit design decision, not silent normal conversation.
- Each agent's first activation chooses wait, fixed greeting, or generated greeting; wait for opening completion and readiness. Re-entry does not replay greeting. Hard hangup/closing wording is agent instructions, not a platform speak-then-end/drain workflow.
- Required startup readiness defaults 30s after join/start attempt, fails early on terminal errors; deliberate opening playback is not a 30s file limit. Genuine caller-idle notification defaults 15s, excluding opening, own speech, holding/dialing/tool wait; instructions choose action, no automatic repeated nudge/hangup.
- limits.max_duration_ms defaults 1800000, definition > tenant > app > platform, pinned per call from actual started_at; includes human-only/held time without reset on transfer. No unapproved unlimited mode/grace warning. Date/current-time tool uses permitted instructions/application time context; no timezone hierarchy or personalization engine.

## Implementation checklist

- [x] Red-test fixed-text input gating and actual playout completion with controllable media fakes.
- [x] Red-test wait/fixed/generated first-message modes with controllable model/media fakes.
- [x] Red-test readiness and maximum-duration clocks with a controllable timer fake.
- [x] Red-test caller-idle clocks and suppression with a controllable timer fake.
- [x] Red-test file playback with controllable time/media fakes.
- [x] Define and validate the closed text/HTTPS-file opening source encoding and pin it into the immutable call plan.
- [x] Define bounded file fetch, accepted audio format, cache, and safe runtime failure behavior before adding file playback.
- [x] Implement bounded file/TTS asset preparation and tenant-safe cache; keep reusable assets distinct from per-call recording retention.
- [x] Integrate the opening gate with wait/fixed/generated greeting modes for the initial receiver.
- [x] Verify the existing current-time tool and implement a permitted immediate-hangup binding.
- [x] Implement planned-call startup readiness and pinned maximum-duration enforcement.
- [x] End planned-call startup immediately after a definitive selected-provider start failure.
- [x] Implement correctly scoped caller-idle notification; keep timing/technical errors safe.

## Acceptance and failure checks

- [x] All consumers—including recorder/archive hooks—receive no participant audio during opening; cached/downloaded/scheduled is not completed playout.
- [x] Omitted opening starts normally; warm providers do not open gate; failed playback does not silently continue.
- [x] Initial activation, duplicate connections, and a new call keep greeting behavior distinct;
  later transfer-agent activation remains owned by the transfer milestone. Closing instructions do not promise audio drain.
- [x] Fake-clock tests separate created_at/start/token/readiness/idle/duration clocks and preserve human-only duration enforcement.
- [x] Cache keys change for voice/settings/tenant changes and never contain credentials; unsafe/unsupported assets fail safely.
- [x] Opening targets entry_caller only; unrelated participants/entry_receiver do not hear it.
- [x] Terminal readiness failure and deadline expiry release attempted resources; deliberate
  opening playback is not mistaken for failed readiness. Duplicate readiness never repeats a greeting.
- [x] Idle excludes opening/output/hold/dial/tool wait and only notifies instructions; it does
  not automatically nudge or hang up.
- [x] Duration precedence is pinned and invocation overrides fail; later definition/tenant/
  application edits cannot reset the running call's deadline.

## Manual verification

1. Run a call with a fixed-file opening, another with cached fixed-text TTS, and another with no opening.
2. Speak during playback and confirm no STT/tool/recording consumer receives that interval; normal conversation begins after playout.
3. Exercise wait/fixed/generated greetings and controlled idle/tool waits.
4. Use short explicit development timer values to verify readiness failure and total duration end without altering defaults.

## Scope boundaries

No wait music, voicemail speech, local VAD/models, mandatory notice/legal-compliance guarantee, automatic templates, platform closing-message API, or new WebSocket transport. Reusable asset caching is not call audio recording.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Partial implementation evidence (2026-09-10): schema `20260910.02` accepts exactly
`{"type":"text","text":"..."}` or `{"type":"file_url","url":"https://..."}`,
rejects mixed/unknown/unsafe forms at their exact path, omits sensitive source values from
routine inspection, and pins the typed value into `ResolvedCallPlan`. The focused compiler
test passed with 2 tests and 0 failures after the expected missing-struct and schema-version
red runs. The runtime outcome is not complete.

The fixed-text runtime starts only after the entry caller attaches an output sink. Its focused
test proves that early audio never reaches STT, early text is rejected, provider/enqueue/start/
progress do not release input, actual sink completion releases both paths, and provider failure
ends the room. At that checkpoint it also proved unsupported file playback and that text without
TTS fails before room registration. The focused file passed with 3 tests; the broader Call Engine
suite passed with 234 tests and 1 integration exclusion.

Initial-receiver greeting coverage now proves all three modes. `wait_for_input` emits nothing;
fixed text is recorded as the exact assistant message and follows the normal text/TTS output
path; generated mode submits a private engine-origin request to the model. Neither fixed nor
generated greeting starts before the entry caller attaches, and both remain behind configured
opening playout. The focused file passed with 5 tests and the complete Call Engine suite passed
with 236 tests and 1 integration exclusion. Transfer/re-entry greeting semantics, file playback,
and lifecycle clocks remain.

Schema `20260910.03` adds a closed authored `platform` tool type. The initial catalog exposes
current UTC time and immediate hangup under participant-local aliases, with the same default-
blocking/explicit-non-blocking admission setting and supervised worker execution as every other
tool. The hangup worker returns a typed effect; ordered start/completion facts reach Room
Authority before it applies the effect and ends the room. Focused runtime coverage passed with
1 test and 0 failures. The complete Call Engine suite passed with 237 tests and 1 integration
exclusion; Calls, Gateway, and Console suites passed with 35, 66, and 56 tests respectively.

Each planned room incarnation now starts one significant `CallLifecycle` process alongside
Room Authority. It owns the startup-readiness and maximum-duration timers from live subtree
startup, retains a deadline that fires before authority binding, and cannot be restarted in a
way that resets either clock. Room Authority mirrors only the readiness gate and reacts to
terminal lifecycle events. Attaching the entry caller satisfies readiness immediately when no
STT runtime is selected; a selected STT runtime must start and bind first. Initial greeting
admission now requires both readiness and opening-audio completion. The duration timer uses
only the immutable plan value and ends the entire room with a typed internal reason.

The focused lifecycle files passed with 3 tests and 0 failures after their expected red runs.
The complete Call Engine suite passed with 240 tests and 1 integration exclusion; Calls,
Gateway, and Console passed with 35, 66, and 56 tests respectively. At that checkpoint,
caller-idle notification, early termination on definitive provider startup failure, the
tenant/application duration precedence source, and file playback remained pending.

Selected STT startup/binding failure now reports a terminal readiness failure through the same
lifecycle owner, cancels the readiness clock, and ends the attempted planned room immediately.
The caller receives the bounded `speech_to_text_unavailable` attachment error while connection
events receive only the safe call-start failure reason. A lifecycle status check preserves the
legacy ad-hoc room behavior, where a failed optional attachment is detached without ending the
room. The new focused test failed first because readiness remained armed, then passed; the
complete Call Engine suite passed with 241 tests and 1 integration exclusion. Calls, Gateway,
and Console remained green with 35, 66, and 56 tests respectively.

The lifecycle owner now arms the configurable 15-second idle clock only while the initial agent
is genuinely waiting on an attached caller. Real text or speech-start activity cancels and resets
the clock. Opening playout, generated/fixed agent output, deterministic holding, and pending tool
execution suspend it. A token claim rejects stale deliveries. Expiry starts one private
engine-origin model turn describing the idle condition; the agent's instructions may choose
speech, silence, or a permitted tool. Completing that idle turn does not rearm another nudge—only
later caller activity permits a new idle interval. No automatic hangup or polling cadence exists.

The initial idle test failed red because no timer was armed. Focused lifecycle/opening coverage
passed with 14 tests and 0 failures, including opening completion, generated greeting, stale timer,
long-tool wait, and speech-start boundaries. The complete Call Engine suite passed with 246 tests
and 1 integration exclusion; Calls, Gateway, and Console remained green with 35, 66, and 56 tests.
Dialing is not available in this milestone; its later implementation must use the same suspension
boundary rather than treating transfer setup as caller silence.

Duration resolution now preserves an omitted authored limit until compilation. Call Engine applies
explicit definition, tenant, application, then platform-default precedence and pins the resulting
1,000–86,400,000 millisecond value in `ResolvedCallPlan`. `vxpipe_calls` obtains application and
tenant values from its trusted `:call_duration` OTP setting while preparing the call; the tenant
map is keyed by the public tenant key. The invocation schema continues to reject a caller-supplied
`limits` field, and room startup has no duration override.

The focused red tests first observed `1800000` at the parser instead of `nil` and then observed the
same premature default instead of the configured tenant value. After implementation, the Call
Engine compiler file passed 13 tests and Calls admissions passed 11 tests. The complete Call Engine
suite passed with 247 tests and 1 integration exclusion; Calls passed 36 tests. A stored prepared
plan remained at 90 seconds after the test supplied changed tenant and application settings,
proving the mutable setting is not consulted after compilation. File opening playback/cache remains
pending.

The file-asset checkpoint pins the first accepted profile to RIFF/WAVE PCM format 1, mono 48 kHz,
16-bit little-endian audio. Defaults are a 6 MiB body, 60-second decoded duration, 5-second bounded
fetch phases, and a 128-entry/64 MiB tenant-scoped in-memory LRU cache. HTTPS fetching disables
redirects, retries, and decompression; validates all resolved addresses as global; and connects to
one selected address while keeping the original hostname for TLS. The cache key hashes tenant,
exact URL, and media-profile revision without retaining the URL.

The first focused test failed at the missing typed asset. A second red test failed at the missing
settings/loader boundary, and the cache-supervision test initially found no application-owned
cache. The completed asset/application files passed 9 tests, and the complete Call Engine suite
passed with 253 tests and 1 integration exclusion.

File opening now starts a temporary worker through the room capability supervisor after the entry
caller attaches its output sink. The worker prepares the tenant-scoped asset outside Room Authority,
feeds PCM chunks of at most 20 milliseconds through the existing output backpressure boundary,
and waits for the sink's actual playback completion. A file source does not require a TTS capability.
Load, output, or worker failure ends the room without opening caller input; unrelated or pre-completion
playback signals do not release the gate.

The new room test first failed at the runtime's explicit `file_url` rejection. The focused opening
room file then passed 9 tests, including caller input suppression, sink-completion gating, the
no-TTS path, independence from an unrelated TTS failure, and a controllable asynchronous load
failure. A seeded complete Call Engine run passed 256 tests with 1 integration exclusion. Cached
generated text/TTS assets and the remaining acceptance checks were still pending.

Generated text now passes through a temporary supervised cache sink. The sink forwards PCM through
the existing live output boundary while collecting no more than the configured asset byte/duration
limits, then stores the completed rendering in the application-owned bounded LRU cache. Cache
identity hashes the tenant, exact text, provider/model/voice and output-affecting settings without
including credentials. A hit starts the ordinary temporary asset player and makes no new TTS
request; actual destination playout completion remains the only event that releases caller input.
The first two-call test failed because the second room synthesized again. The completed focused
opening/asset files passed 16 tests, and the complete Call Engine suite passed 258 tests with 1
integration exclusion. Calls, Gateway and Console passed 36, 66 and 56 tests respectively.

The final audit proves an attached entry receiver receives no opening output and cannot start the
opening; attaching the entry caller sends audio only to its sink. The single ingress gate discards
pre-completion frames before STT and therefore before transcript/archive consumers, while admitted
post-completion audio proceeds normally. Omitted-opening, provider-warmup, controlled failure,
greeting, readiness, idle, created/start-time, and pinned-duration cases remain covered across the
focused Call Engine and Calls suites.

Opening attempts now emit one terminal payload-free telemetry event. Duration/count measurements
carry only closed `source` (`text`/`file_url`) and `outcome` (`completed`/`failed`) metadata; omitted
opening emits none. The focused runtime telemetry test failed first with no message, then passed for
both correlated playout completion and controlled provider failure. Console diagnostics keeps the
bounded aggregate in a dedicated projection and renders source, outcome, latest duration, and count
without retaining call identity or payload data. The final seeded Call Engine suite passed 259 tests
with 1 integration exclusion. Calls, Gateway, and Console passed 36, 66, and 57 tests respectively.
Root formatting, warnings-as-errors compilation, strict Credo, and unused-dependency checks passed;
root tests remained blocked only at Persistence database creation because this shell has no
PostgreSQL password. Rendered diagnostics checks at 1440×1000 and 390×844 showed the new panel in
the existing workbench without horizontal overflow; the browser accessibility audit reported zero
violations.

Pre-delivery review checkpoint (2026-09-12): the runnable development definition now grants its two
sample agents the existing platform `hangup` tool and explicitly instructs them to use it when the
caller asks to end the call. A focused configuration contract prevents that manual lifecycle path
from disappearing. Engine coverage now also proves that the permitted tool completion terminates
the room and drains an `archive_stream_closed` fact; durable projection evidence is recorded in the
asynchronous-history and call-details milestones. A rendered sample call using the real Gemini
model invoked the tool and stopped its WebRTC/media room; the matching durable call-end result was
verified directly in PostgreSQL.

The corresponding client-terminal checkpoint now closes the observable lifecycle as well. When
the room ends, Gateway sends Small WebRTC `peerLeft` on the established RTVI channel before a
bounded transport shutdown. A real ExWebRTC test proves that ordering. The Console treats the
client's resulting disconnect as terminal for the consumed admission and returns to call creation.
The rendered Gemini/Morse hangup path completed without reconnect attempts or HTTP 409 responses;
desktop/mobile rendering, browser-error inspection, and WCAG A/AA checks passed.

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added caller-only playback, readiness cleanup/duplicate greeting, explicit idle exclusions and pinned duration hierarchy tests; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
