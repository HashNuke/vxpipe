# Google STS response ownership

Status: pure response-state owner implemented and locally verified; actual
controller/shared-admission adoption is not implemented. Google remains
unadvertised. This completes neither response delivery, hosted acceptance nor
interruption-history or resumption-watermark proof.

## Problem and required outcome

The current adapter uses one caller/input reference for generated output and
clears it after playback. A model end with `IN_PROGRESS` can precede another
response to the same input, but subsequent audio/text then has no owner. If it
arrives before playback finishes, it can instead enter the completed response's
buffer. An idle guard prevents premature renewal, not lost or mixed responses.

The [pinned ADK receiver](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/models/gemini_llm_connection.py)
surfaces interaction status for prompts spanning several model turns. The
[controller profile](google-sts-controller.md) records the corresponding codec
evidence. Do not fabricate another caller end, send a placeholder, replay input,
or infer that local playback ended the upstream model response.

Required local proof is actual capability-controlled streaming of independently
credited responses, with separate text and generation/playback settlement. A
later response may arrive before the earlier one finishes playback. Caller
finals stay attached to their caller, never an agent response. Thought-only and
tool-only work must not create empty public speech turns.

## Proposed shared boundary

Add an opt-in STS descriptor fact for provider-reported response starts. For that
profile, caller `turn_ended` remains caller evidence and does not itself admit
agent output. A bounded `response_started` event requests output admission; the
engine still issues the fresh output reference after acknowledgement and policy
checks. Other providers retain their existing input-end initiation until they
explicitly adopt the new profile.

Each model response gets an independent private reference, not a caller ID.
Response-start evidence precedes its credited PCM and is not a public event by
itself. Require a monotonic allocation-local response ordinal for bounded
duplicate/retirement handling; a stale ordinal cannot reopen settled work. The
channel validates the descriptor and event shape. The room continues minting
public agent turn/command IDs at actual admission.

Admission must retain an engine-owned authorization origin established before
the response's triggering input is accepted: exact allocation/source, input epoch
and both directional audio-policy intervals. Capturing the current epoch when a
delayed `response_started` arrives is insufficient: it can relabel old work after
hold/regrant. An opaque origin reference may cross the provider boundary; policy
contents and authority remain in the engine. The atomic input-metadata API and
the Google interaction-to-origin association still require design resolution.

Use one capability admission queue. Entries retain immutable origin evidence and
are rechecked at grant. Caller activity, including an accepted external start,
blocks dequeue. Hold, source replacement or revoke/regrant retire queued work,
not pause it for replay. A response-specific rejected/cancelled disposition must
tell the provider to discard that record's bytes and obligations without sending
an upstream interruption for a newer wire generation. This extends only the
existing queued-output authorization task, not unrelated Gateway policy work.

For opted-in allocations, the channel must reject output admission without the
matching acknowledged response-start evidence. Advance the response-index
high-water mark even for starts that the consumer subsequently rejects on
policy. Gaps from non-speaking model generations are valid. Exact duplicate
evidence must not grant twice; a conflicting reference for the same index is
invalid. Retirement must remain bounded rather than retain every old reference.

## Proposed provider ownership

Separate the upstream response currently receiving content from the response
occupying the engine playback slot. A cohesive response owner retains bounded
per-response text, PCM, generation/model boundaries and interruption state.
Only the admitted response may use output credit. Later generated responses
retain their own bytes/text until admitted in order; settling an earlier one
cannot clear a later response or promote its finality.

Keep the existing single credited chunk, 16 pending PCM chunks and 65,536-byte
retained spoken-text budgets across retained response state, not multiplied by
the number of queued responses. Bound response records at 16; overflow fails the
allocation explicitly. Completed records retire after all their model and local
settlement obligations, using bounded state rather than an ever-growing retired
reference set. Tools keep their own invocation ownership and must not force an
empty audio output slot. A record may exist privately for thought/tool work or
buffered output transcription. Only its first PCM announces `response_started`;
transcription alone does not create a public speech turn. A generation that ends
without PCM retires its buffered spoken text without publishing it as heard.
Tool associations use the independent model-response reference, never an invented
caller end; invocation execution/results remain owned by the tool lifecycle.

Model `turnComplete` separates upstream responses; `generationComplete` settles
that response's generated content, and the matching engine settlement closes
its playback obligation. The model boundary still cannot manufacture caller
completion. Interruption fences exactly the affected output/queued evidence;
stale credits or playback for an earlier output cannot mutate the next one.
Successful overlap correlation and provider interruption/history guarantees
remain required; do not replace them with unconditional allocation failure and
claim this design complete.

Resumption eligibility examines every retained response obligation. A completed
A playback must not permit renewal while B still holds pre-admission text/audio,
unacknowledged start evidence or unsettled model/playback boundaries. Neither
current-wire completion nor the active output slot alone proves quiescence.

## Independent design review

2026-09-22, Russell (native Codex Astra xhigh): candidate descriptor/event names
and opt-in split are suitable for shared contract reds, but runtime implementation
is not yet cleared. Required repairs are pre-input authorization origin, one
policy-qualified queue, response-specific discard, acknowledged-start admission,
monotonic retirement and owner-wide resumption. Limit dependency work to milestone
D's not-yet-admitted/queued authorization item. The origin API/protocol association
must be settled before implementation; an opaque token alone does not prove that
uncorrelated delayed wire content belongs to a newly accepted caller.

Also correct the first-response reproduction: do not wait for caller-end output
admission before supplying model content. Prove no output admission on caller end
or transcription alone, then a first response reference distinct from the caller
when actual PCM arrives. Preserve earlier two-response red evidence as history.
These are review requirements, not implementation or hosted acceptance claims.

### Atomic origin delivery and cutover limit

Follow-up source review approves shared contract reds for context-bearing
`Session.push_audio/3`, `push_text/3` and `input_activity/3` overloads using the
closed option `response_context: reference`. An opted-in provider receives the
context and operation atomically through optional `STSProvider.submit_input/3`:
`{:audio, pcm}`, `{:text, request_ref, text}` or `{:activity, boundary}`. Existing
providers retain their old dispatch. Reuse the ordered input slot, not a mutable
out-of-band set-context message. Stage first-use context before invocation,
activate only on acceptance and roll it back on rejection; providers can emit
events before their input callback returns.

The capability reuses one opaque origin while immutable authorization evidence
is unchanged. Response evidence carries that origin alongside its reference and
ordinal. A bounded context owner must retain origins needed by input, response
and tool obligations; acknowledgment alone does not grant current policy.

This does not justify cross-origin wire cutover. A's `IN_PROGRESS` model end can
precede another A response even after local hold/regrant. If B is accepted on the
wire first, unlabelled next content cannot simply be assigned to B. Establish
interaction origin on accepted input before any first model content, retain it
across continued generations, and apply narrow pre-wire backpressure while a
cross-origin cutover is unproven. Successful same-origin response/playback overlap
is required now; successful cross-origin lifecycle acceptance remains open, not
redefined as permanent rejection. An external end closes its original caller
origin; tool results likewise inherit invocation origin, not submission time.

Implementation order: shared atomic input boundary in an isolated worker;
parent-owned pure bounded response assembly/credit state first, then channel
start/grant/discard and capability/provider integration. The pure owner stores
the supplied origin immutably and cannot decide policy or upstream cutover. Its
tests must prove separate wire/playback lifetimes, shared budgets, exact credit
and settlement, non-speaking retirement and all-owner quiescence before adoption.

The input-only foundation initially retains at most 16 accepted distinct origins
until allocation teardown, with unlimited reuse of the same retained origin.
That is an explicit interim bound, not completed origin retirement. Before full
integration acceptance, bind bounded exact response/tool obligation holds and an
engine-authorized last-root retirement operation; prove more than 16 sequential
fully retired origin rotations without evicting live evidence or accumulating
tombstones. Provider-issued references cannot create authorization contexts.

### Capability origin checkpoint design review

Before an opted-in input command reaches the channel, the capability proposes
an opaque context against one immutable fingerprint: allocation generation,
human/caller source, input epoch, and both input and output audio-policy
intervals. The input interval belongs to the sending human; the output
interval belongs to the receiving human, whose incoming route includes the
agent's speech. A proposal does not authorize anything. On successful input
acceptance, the capability retains that context and reuses it only while the
fingerprint is unchanged. A failed first use retains no origin. The input slot
already stages and accepts the exact context around the provider callback.
Legacy descriptors continue to use their existing no-context calls.

Direct (non-framed) capability input begins with the allocation generation as
its epoch; framed input begins only after an explicit `release` supplies its
epoch. Opted-in input requires both directions' current audio routes to be
permitted, including typed text and external activity. A changed epoch/source
or either interval must never silently inherit the previous context. At most
16 distinct interim contexts may be retained, matching the channel's current
input-only bound. Exact response/tool holds and root retirement remain separate
requirements; the interim cap must not be represented as final lifecycle
completion. A later checkpoint must prevent sending another context to an
unlabelled Google wire until old interaction cutover is proven.
Held direct activity is denied even though a direct allocation can otherwise
use its generation as an initial epoch; it cannot create a new accepted origin
after `hold` has cleared the active input epoch.

Rejected alternative: assigning context only when `response_started` arrives.
That would relabel a delayed A response with B's current authority after a
hold/regrant, which no downstream policy recheck could repair.

Checkpoint evidence: eight real-capability focused tests and the 257-test
capability/speech group pass (three integration tests excluded). Independent
Astra xhigh review found an output-interval recipient error and a held-direct-
activity bypass; both were reproduced red, corrected and cleared in source
follow-up. This is only the capability-to-channel pre-input context boundary.

### Google interaction-origin checkpoint design review

The Google Live model stream does not label each response with an input-origin
reference. For a locally opted-in test profile, `submit_input/3` must receive
the shared channel's staged context in the same ordered callback as PCM, text
or external activity. The provider binds the first accepted context before
sending its input to the wire; subsequent input with that exact context may
continue the same interaction even after a model `IN_PROGRESS` end. A new
context is rejected `:busy` before wire send while the old interaction has no
provable cross-origin cutover. Rejected invalid input cannot commit a new
origin. This leaves successful post-hold/new-origin cutover as an explicit later
acceptance requirement, not a claim that permanent backpressure is sufficient.

The descriptor opt-in remains local/unadvertised until actual response-start
emission, capability queue/policy authorization and provider response-owner
adoption work. The ordinary non-opted Google fixture path stays unchanged.
Direct legacy provider input callbacks are rejected for opted-in allocations;
they cannot bypass the context association. The local descriptor choice is a
closed boolean with duplicate keys rejected.
Rejected alternatives are assigning the latest capability context to any
delayed model frame, switching origin at `IN_PROGRESS`, or treating a fresh
caller end as proof that the old wire response has stopped. None supplies a
wire label or a covered resumption watermark.

Local verification: 28 focused Google session cases and the 297-test
Google-provider/shared-speech group pass, excluding three integration tests.
Independent Astra xhigh source review found no remaining actionable issue
after duplicate-key and direct-callback-bypass red/green fixes. This does not
clear actual controller response delivery or hosted interoperability.

## Rejected alternatives

- Reusing the old caller end conflates caller publication and agent generation.
- Clearing the sole output slot on model end discards pending playback and text.
- Appending new response bytes to a generation-complete output breaks credit and
  transcript finality.
- Increasing buffers alone cannot provide missing ownership or authorization.
- A second generic transport or agent coordinator would duplicate existing
  channel and room responsibilities.

## Verification and dependency order

1. Reproduce a dropped second response after first playback and an early second
   response while first playback remains pending, through the real capability
   and fake Google wire. No manual `Session.admit_output` in controller tests.
2. Review the descriptor/event, bounded retirement and policy contracts before
   implementation; add shared channel conformance reds for the chosen shape.
3. Implement the provider response owner and engine admission together, with
   first/typed/external response behavior and caller-final correlation covered.
4. Exercise distinct transcripts/PCM, slow credit, pending playback, multiple
   response boundaries, limits, duplicate/stale starts, interruption, policy
   revoke/regrant, hold and cleanup. Use owning-child red-green evidence.
5. Update the normative provider contract/author guide and milestone; independent
   review, commit, then integrated umbrella gates. A fake-wire pass is not hosted
   or no-loss resumption acceptance.

Research/reproduction evidence belongs in
`labnotes/20260922-2016-google-response-ownership.md`.

The pure `Google.STSResponses` owner has 16 focused checks and passes alongside
the existing Google codec/session/output tests (68 total). Tests cover unfinished
B while A's final credit/playback settles, admitted discard retaining exact
outstanding credit, both model/playback orderings, shared capacity recovery,
40 sequential retirements and bounded ordinal exhaustion. It has no channel or
wire side effects and is not yet adopted by STSSession. The actual controller
first/continued-response requirements remain red and must be completed next.
