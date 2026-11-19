# Provider turn links

Nested Scribe receipt landmarks use the inner recognizer's allocation/turn refs,
while canonical speech events use the wrapper's refs. These identities must be
linked explicitly before joining provider timing to accepted call turns. The
retained identical-text/two-turn regression failed before link emission existed.

ConversationalSTT now reads the existing coordinator's native reference for each
unique canonical emission. This also covers queued turns drained by a different
native event: it does not assume every emission belongs to the incoming event.
No coordinator transitions changed. A bounded reference-only turn_link packet
carries both allocation/turn pairs through the existing capture worker. One last
link is cached to avoid repeated transcript/end links, and new subscriptions reset
the cache. The original capture owner/grant fences link emission.

Focused tests74/0 cover distinct links for identical text, queued-turn mapping,
worker forwarding and unchanged probability/timing behavior. Broader affected suite678/0 (9excluded), static gates and Lean pass.
Astra xhigh final re-review is clean (76focused tests and3independent probes). This supplies explicit identity evidence; room-turn,
response and persisted-report correlation are still pending.

The preceding umbrella run finished exit2 with only the live-inspection baseline
synchronization failure. That test now has a reviewed publication barrier in its
own checkpoint. Persistence578/0, Gateway891/0, Calls424/0 and Console591/0 passed.
Those results predate these turn links and do not establish final acceptance.

Astra reproduced a missing-link path when a native hint preceded VAD onset.
A second retained regression proved the reverse order also needed immediate
association after the hint bound the active turn. Both failed before correction.
The acoustic emission path now uses the same link helper, and native processing
also considers the active canonical reference. Unknown native refs remain absent;
no text matching or invented association is introduced. Both regressions pass.
The new umbrella run started before this final VAD correction and is not frozen
acceptance evidence for the final checkpoint state.
