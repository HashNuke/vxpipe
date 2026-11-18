# Universal replies live acceptance plan

Defined before execution on 2026-11-18. Run through `bin/livetests run` only.
Never inspect or edit the protected credential file. Missing credentials leave
acceptance pending. Preserve failed attempts and report each rerun separately.

## Runtime conversations

Start with Google `gemini-3.5-flash-lite` and OpenAI `gpt-6-luna`; extend the same
harness to the remaining four installed LLM integrations after their transport
checkpoint. Use reviewed `Vxpipe.Providers.LiveModels` selections; these are test
fixtures, not production permission entries.

For each provider, run exactly one buffered and one streaming conversation on a
fresh host-settled modern Session. Declare `lookup` and `hangup` on every round.
Use only a synthetic Northstar office receptionist and reference DEMO-42. The
lookup executor records a single accepted invocation and reports a running native
result; a later trusted observation reports READY. It performs no external action.
Hangup is declared to expose unwanted tool behavior, but must not execute in this
runtime-only scenario.

Fixed steps: short greeting; three-sentence office-hours response; explicit silent
listener/null; listener cue; one lookup and acknowledgment; unrelated arithmetic
while lookup runs; trusted asynchronous completion; idle timeout; cancellation
after model-attempt admission; a subsequent usable response. Assert exactly one
lookup, no other native effects, validated dialogue and explicit host settlement.

Per-step evidence includes provider/model, buffered/streamed mode, selected native
or portable strategy, elapsed milliseconds, model attempt count, reported token
usage and typed outcome. Never print credentials, headers, private replay or raw
provider objects. A failed assertion stops that conversation; the other ExUnit
cases still run. No application-level rerun is hidden from the evidence.

## Remaining gates

These Session tests do not replace configured Calls/Persistence/Console admission,
a real controlled synthetic room invoking Hangup, browser inspection, the shared
six-integration adversarial matrix, router replay checks, or deployment smoke
verification. Keep those milestone tasks open until separately demonstrated.

## Diagnostic comparison after attempt 1

Attempt 1's Google native-object conversations made unwanted native calls and
reached the model-round limit in both modes; the encoded fixture has no forced
ANY tool choice. Before changing production selection, run exactly two additional
Google conversations with the same scenario and options, changing only the private
test strategy to portable JSON (one buffered, one streamed). Keep the native
failures. This comparison tests whether native schema-plus-tools selection is the
cause rather than weakening tool availability or changing the receptionist prompt.

The portable comparison also failed, at a listener cue or post-tool dialogue,
while both OpenAI conversations passed. Run one further buffered/streamed Google
portable comparison with an observational test provider that prints only synthetic
normalized response text and tool names. Preserve metrics from all attempts.
This diagnostic changes neither production strategy nor prompts/tool availability;
its raw synthetic response lines are for diagnosis and are not credential-bearing
provider objects. Keep only aggregate metrics in committed evidence artifacts.

## History-envelope clarification trial

The diagnostic portable runs copied host-history `type` and `participant_id`
fields into post-tool replies. Clarify the shared prompt: final replies have
exactly `agent_mode` and `message`; historical participant and platform envelopes
are input records. Run all six cases once (Google native and portable in both
modes, OpenAI in both modes), keeping the scenario, tools and budgets unchanged.
Retain all earlier failures in the evidence.

## Explicit AUTO comparison

After the clarified-prompt trial, run exactly two Google native cases with
explicit `tool_choice: :auto`. This retains both authorized tools and differs
only from the previously omitted optional toolConfig. The documented default is
AUTO, but this comparison checks whether the upstream schema/tools interaction
behaves differently when the field is explicit. Keep production selection and
all prior failed evidence unchanged.

## Shared format examples trial

Explicit AUTO failed both native cases. Source tracing found no instruction
omission; token counts also increased after the clarification. Add two shared
system-format examples (listener cue and post-tool acknowledgment), without adding
fictional history, changing attribution or removing tools. Run exactly the two
portable Google cases once. Retain the failures and do not treat this trial as
production strategy acceptance.

## Configured protocol fidelity correction

The examples trial failed both portable cases. Review confirmed the adapter
transmits instructions exactly, but self-review found that this new fixture only
supplied authored instructions, unlike configured activations which compose the
captured shared and LLM protocol prompts. Correct the harness to use
Protocol.capture/instructions and attributed Input.participant, and update pending
state at executor submission before the acknowledgment. Revert experimental shared
prompt changes (neither proved a remedy). Run exactly the six baseline/native and
portable comparisons once, excluding the explicit-AUTO diagnostic pair. Earlier
failures remain useful standalone-session evidence, not configured-call acceptance.

Execution deviation: ExUnit inclusion took precedence over the explicit AUTO
exclusion because all cases shared the module tag, so protocol1 actually ran eight
cases, including the extra AUTO pair. Retain all eight; move the shared selection
tag to the six intended cases so future selections are exact. Add tool_choice to
future per-step metrics to distinguish diagnostic variants unambiguously.

## Acceptance assertions review

Independent loopback review proved the initial semantic checks could accept one
long false sentence, a false completed lookup, arithmetic 14 and NOT READY.
Tighten the fixture commands for acknowledgments/arithmetic/status to exact short
answers (case and terminal period are immaterial), and check the long answer's
three sentences and office-hour facts. Keep runtime outcome distinct from new
semantic_outcome in metrics; earlier completed rows only mean Session completed,
not that the scenario accepted the answer. Existing test-case failures are retained.
No live rerun is claimed for these tightened assertions yet.

Review also reproduced reversed opening/closing hours passing the initial keyword
checks. The long-response command now supplies one fixed three-sentence office
statement (over eighty bytes), compared exactly apart from case and the terminal
period. This checks the long-dialogue contract without an unreliable language
grader. Other exact short commands retain their same intended meaning.

## Google usage provenance correction trial

Local raw-HTTP tests reproduced buffered Google dropping explicit usage-reporting
facts (disabling safe correction) and streamed zero-filled missing counts enabling
unmeasured correction. After preserving raw reported-output facts in the SDK
patch, run exactly the two portable Google cases with the reviewed, tightened
fixture. This isolates the correction/protocol path; native strategy selection
is unchanged and still has its separately recorded live failures.

## Configured selection and explicit tool ordering

After the reviewed capability-selection change, run the six intended Google and
OpenAI cases once. Keep the fixed ten-step scenario and full tool set. Clarify the
synthetic author's lookup workflow: first submit the native call and wait for its
running result, then speak the fixed acknowledgment. The caller requests only the
lookup, avoiding a simultaneous instruction to speak the acknowledgment before a
result exists. This responds to usage1's observed acknowledgment without submission;
it does not remove tool assertions or change production prompts.

Record SDK stop-event finish reason, HTTP status and text/tool counts in diagnostic
logs, without raw payloads, headers, arguments or private metadata. Retain every
failed case. This trial does not substitute for the separate real Hangup room.

## Controlled published Hangup rooms

Run one synthetic persisted/prepared room for Google and one for OpenAI. Provision
only temporary encrypted test credentials through the authorized live runner;
save and publish a new synthetic spec, then prepare its pinned modern plan. Attach
a local text caller and request end_call once, with current_time also available.
Assert the actual platform tool starts/completes with status ending and the room
monitor reports termination. No telephone destination, external contact or user
spec is involved. Record provider/model, actual action, elapsed time and result.
This gate is separate from the continuing lookup conversation.

## Explicit resumption after cancellation

Configured1 passed four of six cases. Both Google streaming cases completed the
first nine steps but returned listener/null to the final terse READY request.
The deterministic full streaming HTTP fixture passes, including cancellation and
recovery, without stale idle output. Make the caller's resumption explicit:
resume answering in speaker mode with exactly READY. Retain the same mode/output
assertion, cancellation timing and full tools. Run all six cases once; preserve
configured1's two failures rather than treating them as successful recovery.
# Router provenance diagnostic — router-provenance1

Before implementing private router replay affinity, run exactly four synthetic
requests: configured OpenRouter and Zenmux selections, buffered and streamed once
each. Ask for one native `lookup` call with an empty object; do not execute it or
continue the conversation. Record only configured/reported model identifiers,
explicit provider identity fields, and booleans indicating private reasoning.
Do not log raw response bodies, reasoning, signatures, credentials or headers.
Retain all four outcomes, including transport failures. This diagnostic is not
conversation acceptance and does not close any milestone task.

Result: both OpenRouter requests completed and returned private details plus one
native lookup. Buffered metadata identified provider `Google`; streaming retained
the explicit model but not that provider field. Both Zenmux cases stopped before
HTTP because `ZENMUX_API_KEY` was absent. User direction afterward: defer Zenmux
live checks for now and continue the other five integrations. Preserve its
deterministic coverage and record this as a deferral rather than passing evidence.

## Remaining enabled integrations — remaining1

After direct and router transport tests pass, run six cases under
`--only live_universal_remaining`: DeepSeek, Fireworks and OpenRouter, one buffered
and one streamed conversation each, using the identical ten-step fixture and
reviewed LiveModels selections. Do not alter instructions or expected outcomes
during this run. Retain every step and failure. This extends the already passing
Google/OpenAI matrix; Zenmux live cases remain explicitly deferred by the user.

## Buffered usage validation follow-up — remaining2

After the 96-case deterministic usage matrix passes, repeat exactly the same six
`live_universal_remaining` conversations once each. The only runtime change is
buffered usage reporting/completeness normalization; leave all fixture prompts and
semantic assertions unchanged. This also checks whether the retained DeepSeek
buffered listener-cue failure repeats. Keep all remaining1 failures and every
remaining2 outcome. Zenmux live acceptance remains deferred.

Result: three conversations pass (OpenRouter both modes and DeepSeek buffered).
DeepSeek buffered uses successful bounded correction for unrelated/completion
responses. Fireworks buffered completion and streaming cue end with `length`
and no public text at the unchanged 2,048-token cap. DeepSeek streaming returns
extra host-envelope fields after native lookup; correction correctly remains
forbidden after dispatch. All outcomes are retained; this is not full acceptance.

## Reasoning-cap follow-up — remaining3a and remaining3b

The two explicit `length` failures in remaining2 establish that the original
2,048-token fixture limit can be consumed by private reasoning before any public
reply. Increase the common fixture cap to 8,192 for every integration and record
the configured cap in each evidence row. This changes test configuration only;
production budgets, strict validation, one correction limit and the prohibition
on correction after tool dispatch remain unchanged.

Run exactly two repetitions of the same six remaining-provider conversations
(remaining3a then remaining3b), regardless of the first repetition's result.
Keep model selections, prompts, semantic assertions, tools and the 60-second
logical-request deadline unchanged. Retain both repetitions and all earlier
failures. Report individual case outcomes and failure rates; do not describe
successful acceptance as a guarantee of infallible upstream output. Zenmux live
cases remain deferred. This plan targets reasoning truncation; it does not claim
to fix the separate DeepSeek post-tool extra-field response.

Both repetitions finished with four failures: Fireworks both modes rejected the
8,192-token configuration before HTTP; DeepSeek both modes again returned extra
host-envelope fields after lookup; OpenRouter both modes passed. The proposed
fixture cap was invalid: ReqLLM Fireworks caps non-streaming requests at 4,096 and
our public option validation rejects that warning. Streaming selection is also
validated through the same chat preparation. Preserve this fixture error as an
attempt failure. Add an offline all-six-selection budget preflight and set the
common fixture cap to 4,096. No further live run is included in this completed
two-repetition plan; define a new plan after the lifecycle work and review.
