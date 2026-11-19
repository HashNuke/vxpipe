# Diagnostic source discovery

Automatic attachment needs the exact accepted transport epoch/track, which the
ordinary STT readiness binding does not expose for non-cutover input. Guessing from
allocation IDs would join distinct sources. A prospective one-shot request now
asks the capability to announce its next provider-accepted frame's source metadata.
No audio bytes, transcript or unrestricted provider configuration enter the reply.

Discovery uses a settings-authorized bounded CaptureHandoff owned by the capability.
Only resolved LLM agents pass the same eligibility predicate as worker admission.
There is one pending slot per capability, a250ms deadline checked again after audio
acceptance, and a token-fenced expiry message. Allocation/global-policy/private
ownership fences and current settings are rechecked. Both synchronous and ingress
accepted-frame paths run the observation after normal provider admission. No call
waits for diagnostic capacity or model initialization. The source packet includes
format and mode; operational reuse requires the known ConversationalSTT wrapper's
local-acoustic descriptor. Other providers do not imply an existing Silero stream.

Initial red14/3 (missing API), then focused25/0. Retained probe state is constant-size; the future coordinator must also bound
its request rate and outstanding calls. The broader affected suite passes154/0,
and static root checks and Lean pass. Astra xhigh review is in progress. This exposes a source for attachment; it does not yet discover eligible
rooms automatically, start workers or persist a report. These remain open C work.

Astra proved that policy preparation copied a pending request into prepared state.
Consuming or expiring it before adoption then resurrected a stale occupied slot.
The retained public-API regression failed before correction. Prepared allocations
now start without the probe; retiring/closing an active allocation cancels its
probe and timer. Discarding preparation preserves the active request. Focused
regression/fence tests pass18/0; final broader/static/Lean checks and re-review
are running.

The re-review reproduced a retirement-timeout variant: canceling the active probe
before Session.retire succeeded left original state with an occupied canceled slot
when retirement failed. A retained test delays only the allocation's close call
across the prepared deadline; it failed before correction and passes after moving
probe cancellation into the success branch. Focused regression/fence tests19/0.

Final evidence: affected suite156/0, static root gates and Lean pass. Astra xhigh
final re-review is clean (six independent probes). The preceding umbrella run
predates this checkpoint; engine2670/0, Calls424/0, Gateway891/0 and
Persistence578/0 have passed, with Console still running. It is not acceptance
evidence for these newer discovery edits.
