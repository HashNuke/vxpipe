# Scribe source sample mapping

Initial research was performed while the frozen root suite at e260bee4 ran.
No implementation/test/build files changed until that baseline completed.
Implementation and review evidence follows the original plan below.

A temporary probe using the real conversational Scribe session/wire proves the
missing producer. Three samples accepted before subscription at source9000 and two
after subscription at9003 reach the provider unchanged, but no expected
provider_sample_mapping(inner_generation,3,9003) arrives. The probe fails1/1 for
that missing packet. Evidence: /tmp/vxpipe_scribe_sample_anchor_probe_test.exs and
/tmp/vxpipe-scribe-sample-anchor-red.log. Transfer this case to repository tests
before implementing the change.

Independent Astra xhigh read-only design review confirms the existing ordered
Session.push_frame input slot is the smallest seam. Plan:

- Add an explicit STT-only frame-input descriptor capability and optional provider
  callback; replace the current settings.vad admission heuristic.
- ConversationalSTT always advertises frame support, even VAD off. Cache the inner
  recognizer's configured capability during initialization and retain raw-payload
  fallback for unsupported providers/manual Scribe. Do not query descriptors from
  audio callbacks. STTSession's function presence alone cannot distinguish modes.
- Continuous Scribe emits one anchor only after its existing full input acceptance,
  using pre-increment accepted_samples and the original16kHz source timestamp.
  Keep original bytes/chunking and failure results unchanged; partial wire failure
  must not emit a successful anchor. Direct continuous input uses the same path.
- Retain compact identity/epoch/next timestamp/next sequence and token, not audio.
  Accepted raw input, duplicates, gaps, format/source changes or invalid optional
  metadata retire diagnostics without newly rejecting otherwise accepted audio.
  LiveReport mappings are immutable: do not clear local state and silently reuse
  the old collector anchor. A fresh handoff starts fresh correspondence; repeated
  subscription with the same token preserves it.

Rejected: deriving sample correspondence from receipt clocks, or adding synchronous
observer RPCs to audio callbacks. Channel.observe is asynchronous and cannot serve
as a sample barrier. Maintaining an assumed zero origin fails mid-call enablement.

Acceptance still required: nonzero prefix; VADoff/on without duplicate inference;
direct continuous and manual fallback; same/replacement token; revoked/full capture;
raw/duplicate/gapped input; partial multi-chunk transport failure; exact provider
bytes/control outcomes. Root/static/Lean gates and code review follow implementation.
Acknowledged provider profiles and production collector wiring remain pending.

Frozen baseline verification completed: root mix test at e260bee4 exited0 with
all applications passing (Engine2715, Calls434, Gateway891, Persistence579,
Console591; other apps106/222/35/567/20). The previously intermittent briefing_voice
case also passed. Implementation/test edits began only after that process finished.
This validates the collector baseline, not the forthcoming frame-input changes.

Implementation completed using the planned descriptor capability and existing
ordered frame path. Retained tests first failed for missing capability/anchor
(12 tests, 2 failures), then passed. Continuous Scribe retains exact original
provider bytes and emits only after full acceptance; partial transport failure
cannot emit an anchor. Both direct and conversational paths are covered.

Review reproduced missing identity metadata raising after successful wire input.
A retained missing-track regression failed (15 tests, 1 failure); using optional
map lookup now retires capture without stopping recognition. Final affected
speech/ElevenLabs/capability/diagnostics matrix: 762 tests, 0 failures (9 excluded).
Root format, compile warnings-as-errors, strict Credo and unused-lock checks pass.
Lean model build and behavior replay pass. Root suite for this checkpoint remains
required; the frozen all-green result above predates these changes.

Astra xhigh final code review is clean after that reproduced fix. Independent
review: repository cases25/0 and copied matrix plus seven additional probes22/0,
including actual manual-wrapper forwarding, raw-prefix nonzero origin, detached
identities, capture retirement/recovery, provider settlement and durable settings
disable/re-enable without interrupting audio. No audio is retained by the mapper.
Logs: /tmp/vxpipe-scribe-samples-broad-green.log,
/tmp/vxpipe-scribe-samples-lean.log and
/tmp/vxpipe-scribe-samples-review-final.log.

Acknowledged profiles, production composition and configured-call persistence
acceptance remain open; this checkpoint does not claim live activation.
