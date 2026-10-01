# Scribe local session checkpoint

## Goal and scope

Connect genuine allocation-owned acoustic activity to Scribe realtime recognition.
Keep STS contracts unchanged. Scoped service registration, compiled room startup,
Console STT configuration, short initial utterances and initial idle acceptance
remain required work for the provider milestone.

## Red-green evidence and decisions

- Initial test attempt had incorrect domain-signal field names and failed test
  compilation. Corrected the test fields before counting behavioral red evidence.
- Admission/event/consumer group: three expected failures before local-gap
  support (seed 529323); 33 checks pass afterward (seed 283026).
- New input/session group: seven expected missing-module/startup failures
  (seed 356029); seven pass after implementation (seed 543248).
- Empty initial partial: one failure before harmless empty handling
  (seed 148480); repaired group passes 17 checks (seed 489233).
- Extended session/input/descriptor verification: 21 checks pass (seed 325398),
  including actual native CPU classification of the existing public speech fixture,
  bounded queued PCM, twenty-second segment settlement, hard death and old/new refs.
- Fresh per-turn context test: one expected failure before socket renewal
  (seed 940291); session/input group then passes 12 checks (seed 470019).
- STS eager-event defensive check: one failure before local evidence was fenced
  ahead of generic eager-event admission (seed 687967).
- Model preparation uses allocation command tasks separately from the detector's
  single inference slot; a completed preparation task does not occupy that slot.
- Recognition queues retain old refs until final settlement. Genuine new onset
  publishes immediately; queued PCM waits for a fresh connection acknowledgement.
- Detector silence is sample based; missing PCM and transcript latency never
  create silence. No finite-input or eager/resume capability is advertised.

## Selected live evidence

Only the new acoustic/session file was selected with the existing live runner.
No credential file was read or modified directly, no other provider lane ran,
and no speech fixture was regenerated.

- Initial two-turn case: one failure in 8.9 seconds, seed 21170. Both boundaries
  settled, but the known public-fixture word check failed.
- A diagnostic-message edit had a syntax error. That invocation failed compilation
  before any new provider request; the formatter also correctly rejected it.
- Corrected diagnostics: one failure in 8.9 seconds, seed 547394. Safe metadata
  showed first final text 30 bytes with the known word, second final text empty;
  both acoustic durations were 1,920 ms. Server cause is not established.
- Chose a fresh recognition connection for each acoustic turn. Segment contexts
  remain reusable only within their own longer acoustic turn. Retired connection
  messages cannot be attributed to the next turn. Sockets remain allocation-owned.
- Repaired case: one passing test in 9.0 seconds, seed 172613. Two actual acoustic
  starts, two distinct refs, two settled local-gap ends, known word in both.
  No passing paid case was repeated afterward.

## Barriers and verification

- A diagnostic `mix run` from the child in the development environment could not
  find the runtime configuration's Persistence module. The same offline probe in
  the already built test environment worked: one acoustic endpoint, 1,920 ms,
  77,824 recognition PCM bytes. This is a command/build-path issue, not a TCP block.
- Strict Credo initially found descriptor complexity 21 against limit 20.
  Extracted endpoint provenance validation without changing its admitted modes.
- Completion gates and final focused results are recorded below when terminal.

### Terminal focused and fast gates

- Provider/admission/consumer/STS group: 106 tests, zero failures, ten excluded,
  seed 609275. Existing STS conformance remains green.
- Root format check, compile with warnings as errors, strict Credo and unused
  dependency check all terminate successfully. Strict Credo checks 1,176 sources
  and reports no issues after the extraction.
- Lean build/oracle/replay terminates successfully: one test, zero failures,
  seed 916049. This is the existing speech verification lane; no new formal model
  for the private acoustic classifier or Scribe queue is claimed.
- Documentation file links and whitespace checks pass. The unrelated docs-site
  user edit remains unchanged and is excluded from this checkpoint.
- Full umbrella run is still in progress. Its completed CallEngine group passes
  1,805 reported tests, zero failures, 62 excluded (190.7 seconds); Calls passes
  120 tests. Do not treat the unfinished root run as terminal acceptance.

### Full umbrella gate failure

The first root run terminates with exit 2, seed 705441: 3,012 reported tests,
one Gateway failure and 93 exclusions. All other application groups pass.
The failure is the existing five-participant HTTP/WebRTC handoff case at its
post-disconnect 250 Hz wait-audio receive deadline (2 seconds). The audio evidence
reports an unheld connection, generation 4662 and RTP sequence 15. Source cause
is not established. The selected Scribe tests and CallEngine suite are green.
The failing Gateway case is being checked separately at the same seed; this
failed root run is not accepted as a passing completion gate.

### Handoff isolation

The same-seed focused handoff command terminates successfully. Its initial run
and two bounded repetitions each pass one selected test (168.4, 16.8 and 17.3
seconds respectively), with 67 other file cases excluded. No Gateway code or
receive deadline is changed. This establishes non-reproduction in those runs,
not a cause or a repair of the earlier audio timeout. A same-seed full umbrella
rerun is now in progress to resolve the concrete remaining completion gate.

### Rerun and opening-voice repair

The same-seed second root run terminates with exit 2: 3,012 reported tests,
one CallEngine failure and 93 exclusions. Gateway passes all 522 reported tests.
The text opening recording case attempts synthesis before its TTS capability
acknowledges readiness, causing `:not_ready` and room closure. This is a concrete
startup defect, separate from the earlier handoff timeout.

The repair and focused evidence are recorded in
[opening readiness labnotes](20261001-0328-opening-tts-readiness.md). Opening
voice preparation now waits for its own readiness resource in the existing
preparation task. All 24 opening-audio cases pass, seed 445906. Final root gates
are being run against the repaired checkpoint; neither failed full run is
accepted as milestone completion.

### Repaired checkpoint acceptance

The repaired full umbrella command terminates with exit 0, seed 705441:
3,013 reported tests, zero failures and 93 exclusions. CallEngine passes 1,806
tests; Gateway passes 522. Format, warnings-as-errors compilation, strict Credo
(1,176 sources) and unused dependency checks also terminate successfully. The
existing Lean build/oracle/replay passes one test, zero failures, seed 867759.
All 215 local Markdown links in changed documents resolve. The unrelated
docs-site edit remains untouched and unstaged.

This accepts the provider-session checkpoint and opening readiness repair only.
Scoped STT registration, compiled room and Console activation, short initial
utterances, initial idle lifetime and final milestone acceptance remain open.
