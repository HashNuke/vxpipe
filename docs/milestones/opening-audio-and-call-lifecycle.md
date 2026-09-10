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

- [ ] Red-test opening input gating and playout completion, first-message modes, readiness/idle/duration clocks with controllable time/media fakes.
- [x] Define and validate the closed text/HTTPS-file opening source encoding and pin it into the immutable call plan.
- [ ] Define bounded file fetch, accepted audio format, cache, and safe runtime failure behavior before adding file playback.
- [ ] Implement bounded file/TTS asset preparation and tenant-safe cache; keep reusable assets distinct from per-call recording retention.
- [ ] Integrate opening gate, greeting modes, existing current-time tool and permitted hangup binding.
- [ ] Implement pinned duration and correctly scoped readiness/idle events; keep timing/technical errors safe.

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

## Specification review

Reviewed independently by milestone_review_b on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added caller-only playback, readiness cleanup/duplicate greeting, explicit idle exclusions and pinned duration hierarchy tests; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
