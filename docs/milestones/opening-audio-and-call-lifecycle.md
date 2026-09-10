# Opening audio and call lifecycle

Status: in progress. Specification review: approved (2026-09-08).
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
- [ ] Red-test file playback and caller-idle clocks with controllable time/media fakes.
- [x] Define and validate the closed text/HTTPS-file opening source encoding and pin it into the immutable call plan.
- [ ] Define bounded file fetch, accepted audio format, cache, and safe runtime failure behavior before adding file playback.
- [ ] Implement bounded file/TTS asset preparation and tenant-safe cache; keep reusable assets distinct from per-call recording retention.
- [x] Integrate the opening gate with wait/fixed/generated greeting modes for the initial receiver.
- [x] Verify the existing current-time tool and implement a permitted immediate-hangup binding.
- [x] Implement planned-call startup readiness and pinned maximum-duration enforcement.
- [x] End planned-call startup immediately after a definitive selected-provider start failure.
- [ ] Implement correctly scoped caller-idle notification; keep timing/technical errors safe.

## Acceptance and failure checks

- [ ] All consumers—including recorder/archive hooks—receive no participant audio during opening; cached/downloaded/scheduled is not completed playout.
- [ ] Omitted opening starts normally; warm providers do not open gate; failed playback does not silently continue.
- [ ] Re-entry/new-agent/new-call greeting behavior remains distinct; closing instructions do not promise audio drain.
- [ ] Fake-clock tests separate created_at/start/token/readiness/idle/duration clocks and preserve human-only duration enforcement.
- [ ] Cache keys change for voice/settings/tenant changes and never contain credentials; unsafe/unsupported assets fail safely.
- [ ] Opening targets entry_caller only; unrelated participants/entry_receiver do not hear it.
- [ ] Terminal readiness failure and deadline expiry release attempted resources; deliberate
  opening playback is not mistaken for failed readiness. Duplicate readiness never repeats a greeting.
- [ ] Idle excludes opening/output/hold/dial/tool wait and only notifies instructions; it does
  not automatically nudge or hang up. Duration precedence is pinned and invocation overrides fail;
  later definition/tenant/application edits cannot reset the running call's deadline.

## Manual verification

1. Run a call with a fixed-file opening, another with cached fixed-text TTS, and another with no opening.
2. Speak during playback and confirm no STT/tool/recording consumer receives that interval; normal conversation begins after playout.
3. Exercise wait/fixed/generated greetings and controlled idle/tool waits.
4. Use short explicit development timer values to verify readiness failure and total duration end without altering defaults.

## Scope boundaries

No wait music, voicemail speech, local VAD/models, mandatory notice/legal-compliance guarantee, automatic templates, platform closing-message API, or new WebSocket transport. Reusable asset caching is not call audio recording.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
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
ends the room. It also proves unsupported file playback and text without TTS fail before room
registration. The focused file passed with 3 tests; the broader Call Engine suite passed with
234 tests and 1 integration exclusion.

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

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added caller-only playback, readiness cleanup/duplicate greeting, explicit idle exclusions and pinned duration hierarchy tests; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
