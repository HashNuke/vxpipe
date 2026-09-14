# Incremental media policy application

A room membership revision is not a request to restart every media service. The
runtime compares the previous and candidate permissions for each source and
recipient, then applies only the affected changes. This follows the user's
pre-delivery correction to the original revision-wide reset behavior.

The room retains its monotonically increasing snapshot revision for admission and
acknowledgement ordering. Within it, stable permission intervals identify the last
revision that changed each service's relevant rules:

| Path | Relevant difference | Action |
| --- | --- | --- |
| Speech recognition and its ingress | Source presence, transcription demand, that source's transcript routes, transcript storage permission | Keep unchanged sessions and queues; stop when demand disappears, start when it returns, replace a demanded session only across an actual transcript permission boundary. |
| Audio normalization | Source presence, outgoing audio routes, recording permission | Preserve unchanged pipelines; discard affected buffered input before acknowledging a changed boundary. |
| Audio output | Recipient presence and incoming audio routes | Preserve unchanged encoders/playback; replace and clear only output paths whose permissions changed. |
| Recording | Recording permission | Preserve the continuous stream and permitted queued chunks; close the recording gate and discard denied intervals. |

Membership alone does not change an unrestricted route rule. The mixer and
transcript router still check current participant presence before delivery. Private
transfer preparation remains excluded from main-room participation until acceptance
and the commit barrier finish.

Frames and provider signals retain the relevant permission interval, rather than
being invalidated by unrelated room revisions. Restricting and then restoring a
permission creates distinct intervals even when the final rules equal earlier
rules, so denied or stale buffered content cannot be replayed after relaxation.
Current speech intervals remain available for transcript provenance even across
many unrelated membership changes; old historical snapshots remain bounded.

Increasing timeouts leaves external network latency on the admission path. Moving
all restarts to background tasks avoids that timeout but still interrupts healthy
services. Neither meets the requested incremental behavior. The asynchronous STT
connector remains useful only when an actual permission change requires a new
provider session.

Implementation checkpoints:

- [x] Compute scoped permission intervals while retaining the admission revision.
- [x] Preserve unchanged speech sessions, ingress queues, and transcript provenance.
- [x] Apply the audio intervals to normalization, output, mixing, and recording.

Verification passes all umbrella completion gates: 1,006 tests, zero failures,
15 integration cases excluded. A live Gemini/Deepgram two-browser handoff reaches
`Main room active`; the caller retains the same STT transport and audio input/output
pipelines through admission and source-agent departure. Both peers exchange RTP.
See the [speech labnote](../labnotes/20260913-1940-incremental-media-policy.md) and
[audio labnote](../labnotes/20260913-2001-incremental-audio-policy.md).

The transfer-readiness implementation adds an STT preparation path before policy application.
It starts only an affected, still-demanded replacement and waits for its provider readiness while
retaining the installed session. Policy application adopts that prepared generation; it does not
start another connection. An unchanged live or pending session survives unrelated room revisions.
Refreshing a stale candidate updates its pending policy binding without repeating provider startup.
See [the preparation contract](readiness-resource-contract.md#preparing-an-affected-speech-policy).
Other enforcers and startup/transfer coordination remain incomplete in that milestone.

An initial handoff graph can become stale while its resources are being prepared. The transfer
coordinator now recaptures the candidate under the original worker, owner and deadline. It retains
partial preparation leases across that retry, lets each resource reconcile its actual policy diff,
and discards leases omitted from the successful replacement graph. Removed private STT demand
stops its pair; an unrelated revision retains the prepared provider transport and room services.

Discarding the whole partial graph before retry was rejected: it closed the healthy prepared STT
transport and required another provider connection acknowledgement. Retrying arbitrary failures or
extending the deadline would also violate the handoff contract. Only stale-candidate/changed-room
results trigger this path. Callers using `Preparation.run_candidate/3` keep immediate failure cleanup;
the handoff owner uses `prepare_candidate/3` and owns its returned partial leases. Existing owner
monitors and deadlines still bound cancellation and cleanup.

The focused initial-preparation regressions verify retained transport, worker, audience wait scope,
room resources and deadline, plus successful cue/activation for both relevant and unrelated policy
changes. See the [implementation labnote](../labnotes/20260914-2155-handoff-preparation-policy.md).


After participant/policy adoption, media remains held until the release worker revalidates the
current resource graph. A policy revision before any gate opens now restarts waiting, reconciles
against the already authoritative policy and drains a fresh cue before release. It uses the live
preparation path without repeating participant promotion or candidate installation. Unrelated
revisions retain installed providers and room/media actors; changed transcript permissions replace
only the affected STT transport and await its readiness. The same attempt and deadline apply.
Failures once connection release begins still close the room because admission may be partial.

Three focused engine cases and three native WebRTC cases cover removed speech demand, unrelated
policy and changed but still-required speech. The native peers resume bidirectional audio while
retaining their media actors. See the [release-policy labnote](../labnotes/20260915-0137-handoff-release-policy.md).
