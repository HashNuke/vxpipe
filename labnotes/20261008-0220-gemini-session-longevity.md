
## Scope and design review

Read the complete session-longevity brief before implementation. Preserve the
three user-owned Console fixture/diagnostic edits and commit them with verified
work. Preserve the unrelated Wrangler labnote. Never inspect the private env file;
only bin/livetests loads it for the selected child. The user approves one hosted
Gemini-only 15–20 minute lane, separately tagged live_long and its own selector.
No ordinary provider tag, carrier provisioning or timeout increase is appropriate.

Verified Google's session-management and WebSocket references: use server-side
sliding-window compression, provider goAway/timeLeft and the latest private safe
resumption handle. Remove both local lifetime timers. Keep the existing five-second
actual reconnect budget and explicit failure on lost/revoked/unsafe handles;
unsupported history reconstruction must not silently create a fresh conversation.

Pending rotation continues ordinary input. Actual replacement holds at most the
one ordered unsent input command until setupComplete, retaining existing channel
backpressure; accepted old audio is never replayed. Monitor its submitting owner
so abandoned input cannot be delivered later. Retain response/playback/tool/caller
fences and original privacy context. Add bounded success telemetry without handles.

Ambiguity cannot clear on another unqualified model end. Track a genuinely new
exchange begun at an otherwise settled idle boundary, including PCM preceding VAD.
Only attributable caller completion, fresh model content, explicit idle and settled
output can discharge the earlier ambiguity. Preserve all existing stale/overlapping
end protections. Compression and lifecycle changes belong to the Google boundary;
no broader participant restrictions or new dependency is needed.

Initial red: ten focused tests fail for the expected missing compression, audio
busy, held-command busy, fixed timer shutdown and latched ambiguity reasons
(seed 44264). No implementation preceded these reds.

## Local implementation evidence

The initial ten reds pass after enabling sliding-window setup, deleting both
local lifetime timers, accepting input while rotation is pending, and holding one
unsent command until replacement setupComplete. The held command retains the
ordered channel's backpressure; its submitter is monitored and old accepted input
is never replayed. Successful setup emits a bounded handle-free rotation counter.

The clean-exchange red initially remained failing: the old interrupted exchange
never supplied model content, leaving its awaiting-model flag true even at idle.
Candidate start therefore permits that stale flag only when ambiguity already
exists and all caller/final/model-idle/output/tool boundaries otherwise settle.
It cannot authorize rotation. The genuinely new exchange must supply fresh model
content and fully settle before clearing ambiguity. Existing stale-end/overlap
guards remain green.

Continuous digital silence exposed a separate checkpoint problem: accepted zero
PCM reset idle/handle and awaited a transcription that silence never produces.
Two owning session reds reproduced it. Send all PCM normally, but leave checkpoint
evidence unchanged for exactly zero PCM; any nonzero sample keeps the original
guards. Existing synthetic caller fixtures now use a nonzero sample where they
intend unresolved speech. No VAD/amplitude guess or timeout increase is introduced.

The full Google codec/session/controller group passes 175/0 (seed 44264). Three
older assertions were updated to the new contract: pending input is permitted;
actual-switch hold is covered by asynchronous request tests; missing-handle failure
uses a fifty-millisecond provider goAway deadline rather than capping the pending
phase at the reconnect budget. Private-first-context rollback is still verified
with a provider-rejected malformed frame. The new long lane compiles cleanly and
is excluded from ordinary selection (175/0, one exclusion).

## Hosted acceptance in progress

Started the explicitly approved eighteen-minute hosted lane, seed 120002. No
carrier/Funnel setup is selected. It streams a recorded greeting every fifteen
seconds and microphone PCM every twenty milliseconds, services output credit and
settles actual received PCM, checks twenty-second reply bounds, and requires at
least one natural goAway rotation. No text/API-only substitute or silent hold of
the microphone is used. Long tags are excluded by default in Call Engine too.
The first two minutes yield eight completed audible replies.

The unrelated Wrangler labnote remains untouched. No private env contents are
read, no competitor research is included, and no other live provider lane is run.

## Wire-contract discoveries and repair

The first full hosted run lasts 1080.7 seconds with 72 completed replies but
fails the rotation counter (seed 120002). The observer obtained Session.provider
before the ready event and captured nil. Subscribe only after setup acknowledgement;
no sleep is appropriate. This measurement bug does not establish whether a natural
notification was sent in that run.

Short controlled probes expose two independent adapter assumptions: real
turnComplete messages omit interactionStatus, and only the initial periodic session
token arrives during the first thirty seconds. Input invalidation discards that
token. Two codec reds and three controller reds reproduce these contracts; the
five targeted controller cases then pass. Keep the latest token across accepted
input, revoke it on a non-resumable update, and continue enforcing independent
caller/model/tool/playback fences. Decode omitted status distinctly; accept it
only for same-allocation resumption, never origin/policy cutover. Existing explicit
unspecified/in-progress/deprecated and stale-end guards remain.

The next live replacement gets code 1008: the prior session is still connected.
Temporary bounded close diagnostics redact opaque tokens. First retire with a
WebSocket close handshake instead of supervisor kill. Four local reds precede
that change. A further red demonstrates acknowledgement arriving before old
socket termination; wait for both signals, explicitly close transport before ack,
and retain one unsent frame throughout. All fifteen selected local socket/session
cases pass. Do not rely on terminate/2 for correctness.

Google still briefly reports active-client registration after that shutdown.
Two more reds reproduce the precise rejection classifier and retrying its same
handle. The optional private socket close callback passes the reason only to a
requesting provider classifier; Google publishes a fixed safe atom, never raw
text. A rejected socket must terminate before the next attempt. Retry solely this
known state inside the unchanged original deadline. Unrelated policy errors and
other setup rejection still fail closed. The sixteen selected local cases pass.

Live marker probe passes in 30.7 seconds, seed 431707: remember violet before
rotation, resume using the initial token, then independently ask for the word.
One transient active-client rejection precedes successful setup around three
seconds; the resumed model remembers violet and emits credited output. This
confirms the token restores later context rather than an initial local snapshot.
No history/audio/tool replay, new context, timeout increase or polling sleep is
used. Temporary observed-socket and raw-wire scaffolding are removed.

The final long scenario controls one goAway notification at seven minutes if a
natural rotation has not already occurred. Server lifetime timing is not a
project-owned invariant; real token validation, replacement, microphone streaming
and continuing replies are. Report the controlled trigger explicitly and keep the
eighteen-minute duration, twenty-second reply budget and rotation assertion.
The short context probe has its own live_gemini_resumption tag, inherits live_long
exclusion and is never selected by ordinary Gemini/provider tags.

## Umbrella verification follow-up

Formatting, warnings-as-errors compilation, strict Credo, unused dependencies and
Lean build/oracle/replay pass. The first default umbrella run exercises 3292 cases
(seed 492336), with one unrelated media-policy test failure: the actor was already
stopped before the test attached its monitor, giving noproc instead of killed.
Move that monitor to actor creation, before registration/candidate preparation.
The owning authority suite passes 45/0 with the same seed. No runtime contract or
lease/assertion timeout changes. The full same-seed umbrella rerun is in progress;
Call Engine already passes 1961/0 with 74 exclusions.

The second umbrella run finishes with Call Engine green and one Gateway failure:
the local Twilio cue-loss recovery harness observes the earlier nineteen-byte
"Connecting support." request and Flush, but no recovery Speak within its existing
five-second deadline. A focused run fails earlier at private briefing readiness;
a second passes. Strengthen the recovery helper to assert that the model request
is the failed tool-invocation completion, rather than any queued model request.
The strengthened case passes once and then six consecutive same-seed repetitions.
These results do not establish a runtime cause or a repair of the separately
recorded native transfer intermittence. No carrier call or timeout change is used.

Reviewing the combined live harness finds that its short-probe mode accidentally
also selects the long case, since both use an integer controlled-trigger offset.
Select the text-memory probe only for offset zero; the long case continues using
recorded caller speech. Start the final eighteen-minute hosted selection with
seed 485926. Its first minute produces four credited replies.

At 420 seconds the final long run has 28 completed replies and a retained token,
no caller/model/tool/playback obligation, and omitted interaction status. The
controlled goAway notification triggers genuine Google retirement/reconnection;
setup acknowledges around 421 seconds. The telemetry observer records one resumed
connection. Continue the same allocation to eighteen minutes; acceptance remains
pending until the final reply, frame and transcription assertions pass.

Final hosted acceptance passes, 1080.7 seconds, seed 485926: 72 credited PCM
replies, at least fifty final input transcripts, 50,776 continuous microphone
frames, and one successful resumed connection. The latest reply is within thirty
seconds of eighteen minutes and no output remains unsettled. The controlled
notification is reported as true; do not claim naturally observed server expiry
or remote carrier playout. No telephony, other live vendor or raised timeout.

The final clean context-retention selection also passes: 30.8 seconds, seed
107378, one resumed connection around three seconds, a remembered pre-switch
word and real credited PCM. It uses the ordinary real Google socket after all
temporary wire diagnostics were removed. No further live lane is necessary.

Final owning Google codec/session/controller and local WebSocket integration
selection passes 198/0 in 3.9 seconds (seed 70174). It exercises no live vendor.
Run all five root checks plus Lean serially against the final tree; the full
default suite uses the original seed 492336 so earlier failures remain comparable.

## Final checkpoint

All five root gates and Lean pass against the final code. Default umbrella:
3292/0, 120 exclusions, seed 492336; Call Engine 1961/0, Gateway 577/0,
Console 221/0. Lean builds all four jobs, finds no oracle drift and passes the
conformance replay (seed 231893). Formatting, warnings-as-errors compilation,
strict Credo and unused-dependency checking pass. The six focused cue-loss
repetitions and final umbrella pass do not establish a runtime fix for the
separately recorded native transfer intermittence.

Hosted acceptance is checked off separately from long phone acceptance, which
remains open; the parent milestone and index remain incomplete. Review the exact
29 staged paths, include the user's three Console edits and this labnote, and
preserve the unrelated untracked Wrangler labnote. The user authorizes the
verified coherent commit. No dependency, credentials, competitor research, local
absolute path, generated media or build artifact is included.
