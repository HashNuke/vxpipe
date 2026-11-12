# Voice agent guardrails research

Date: 2026-11-11. Scope: research and specification only; no runtime implementation
or commit requested. Preserve the pre-existing staged OAuth implementation and docs.

## Checkpoint: source investigation

- Ran `bin/setup` successfully for this checkout. No live credential file was read
  or modified. No hosted inference request was made.
- Read the milestone index, relevant runtime/editor/history/provider milestones,
  current handbook and implementation boundaries. Capability inheritance replaces
  the complete participant selection; it does not merge provider options.
- Current sentence output is released before the complete response. Output checks
  therefore need both a pre-TTS publication barrier and a model-context acceptance
  boundary; adding an after-the-fact transcript classifier would be insufficient.
- Inspected three external source snapshots, identified only as references A, B
  and C in repository artifacts at the user's request. Found global prompt rules,
  pre-generation/stream interception hooks, and typed classifier adapters plus
  context gates. These are useful mechanisms, not evidence of a complete audited
  input/output policy workflow. Do not infer absence across every extension.
- Verified Jev against the first-party System One API, Noul, model, confidence,
  error and guardrail cookbook documentation. Search initially returned unrelated
  sites using the same name; excluded those from the integration contract.
- Verified OpenAI Decisions against the official guide and endpoint reference.
  Use Noul's `noul` and predicate's `probability`, respectively. Neither should be
  replaced with a choice/score `confidence` statistic. The product field remains
  **Confidence threshold**, as requested.
- Several Markdown pages failed through the browsing reader; direct HTTPS fetches
  and the HTML documentation succeeded. Provider protocol facts were cross-checked
  against source adapters. Reference defaults can lag first-party model catalogs.

## Decisions being specified

Separate guardrail model capability with call-default inheritance; participant-owned
input/output question lists; inclusive probability comparison with default `0.70`;
input feedback or fixed response; complete-output hold with bounded regeneration;
explicit errors, cancellation and transcript/inspection provenance. Native audio
generation remains deferred. Provider and model choices are not silently substituted.

## Checkpoint: specification and local review

- Wrote the [durable decision](../docs/design/voice-agent-guardrails.md) and
  [implementation milestone](milestones/voice-agent-guardrails.md). Added the
  unchecked milestone before delivery/retention and recorded design review
  separately from implementation in the index.
- Chose whole-response output gating because streamed sentence delivery cannot
  retract audio. Rejected prompt-only enforcement, speculative generation before
  input approval, choice-confidence thresholds, sentence-only checks, fail-open
  errors and replaying the tool turn during regeneration.
- Review found that a coordinator-only output gate is insufficient: the generic
  runtime commits assistant history separately. Specified a candidate acceptance
  port, request-local rejected drafts and tool-free rewrites that preserve durable
  tool effects. Fixed responses also receive output checks; their rejection never
  invokes the LLM. Generated greetings/idle/tool completions are covered explicitly.
- Specified per-recipient checks, final-input revision identity, safe feedback
  origins, owned cancellation, no stale publication, bounded checker/rewrite
  deadlines and permitted live/archived evidence. An unavailable checker ends the
  response without unchecked speech; it is not a semantic rule match.
- The first index consistency check caught a pre-existing stale summary: its 59
  entries actually had 47 complete and 12 incomplete, rather than 46 and 13.
  Recounted from actual checkboxes; adding this proposal gives 60 = 47 complete +
  13 incomplete. No existing implementation checkbox changed.
- The pre-existing staged OAuth work became commit `26b9bd31` during this task.
  This research neither staged nor committed it. Final changes remain limited to
  the new research/design/milestone files and the milestone index.

## Requirement coverage

| Requested requirement | Specification location |
| --- | --- |
| LLM-backed participants first; native audio later | Runnable outcome and selection validation |
| Participant enablement and model inheritance | Configuration contract; Settings experience |
| Questions, two-decimal confidence thresholds, default 0.7 | Questions and confidence thresholds |
| Check transcripts before LLM input | Input admission and evaluation identity |
| Failed input feedback for agent response | Input `agent_response` and typed feedback code |
| Configured direct TTS response | Input `standard_response`, with zero conversational LLM requests |
| Output feedback and regeneration | Output acceptance port, retry bounds and no tool replay |
| Original input, decisions and responses in transcript/debug | Transcript, persistence and debug contract |
| Research the three requested reference implementations | Anonymized A/B/C source revisions and mechanism comparison in the decision |
| Jev and OpenAI Decisions | First-party endpoint/model contracts and both adapter acceptance gates |
| Runnable milestone and ordering | Four vertical checkpoints, acceptance matrix and updated index |

## Verification evidence

Documentation-only checkpoint. `bin/setup` completed successfully; direct source
and first-party documentation inspection support the findings. No runtime/UI
changes, paid API requests, hosted inference, model-quality measurements or browser
acceptance were performed. Runtime, frontend, Lean and hosted checks are future
implementation gates, not claimed results of this research. No commit requested
or created.

Final checks passed:

- Three new documents: 22 relative links/heading anchors resolve, both fenced JSON
  examples parse, and Markdown fences/whitespace checks pass.
- The ordered index has 60 sequential entries, 47 checked and 13 unchecked.
  All nine prerequisite/reference milestones precede the new entry; all existing
  checkbox states are unchanged. All 16 new implementation tasks remain unchecked.
- No prohibited reference-framework names or local absolute paths occur in the
  new documents. The research comparison retains anonymous source revisions.
- `git diff --check` passes. Final status contains only the three new documents
  and the milestone index change; no research paths were staged or committed.
- Requirement-by-requirement review against the request covers both APIs, settings,
  both input actions, output regeneration, transcript/debug history and native-audio
  deferral. Remaining runtime/provider/browser checks are explicitly future gates.
