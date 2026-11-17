# Structured agent messages

## Requirement and source findings

- User clarified that provider `user` means platform-supplied input, including
  messages on behalf of a human or the app; `assistant` output must also be
  structured. Continued specification work rather than changing runtime behavior.
- Inspected request construction, origin projection, model context, tool
  continuations, normalized responses and compaction. Origin exists internally
  but is not projected; tool completions are user-role prose/JSON observations;
  final ModelResponse currently requires text or tools.
- Installed ReqLLM exposes structured generation APIs; no provider conformance
  or native-tool/streaming compatibility was inferred from that fact.
- Asked which additional application concerns need representation. Proceeded
  with the established participant/platform, turn/overlap, playback and tool
  scope; further model-authored fields remain subject to explicit requirements.

## Initial draft and user refinement

- Initially drafted a focused structured-message design: versioned events with explicit
  source and type, runtime-owned metadata distinct from untrusted payload data,
  and response decisions distinct from admitted/delivered speech.
- Preserved exactly `interrupt_agent` and nullable `response_text` as the model's
  final dialogue payload. Runtime adds identity/correlation; ordinary requests
  without eligible overlap require false. Native tools and cue selection retain
  separate typed operations. No model field can authorize routing or playback.
- Applied the shared input shape to the classifier example. Linked TTS/cue
  contracts and the delivery review; A owns common attributed input/history,
  C owns the full selected-profile protocol, and F covers compatibility/latency.
- Initially added four checkpoint tasks and strengthened existing acceptance, for 76
  pending tasks in the same six useful checkpoints. Recorded the earlier clean
  72-task review as historical; the amended plan requires a new review.
- Explicitly recorded complete-result validation's first-audio cost. Raw JSON
  deltas cannot reach TTS; incremental framing needs its own reviewed contract.
  The one-second target remains unchanged. Legacy profiles are explicitly pinned
  and missing historical identity/delivery remains unknown.

## Simplified final proposal

- User explicitly requested a separate, simple format with no model-visible turn
  information. Rewrote the design around role plus structured content. Removed
  event IDs, turn/revision/sequence fields, source wrappers and version fields
  from message examples; the application keeps those concerns internally.
- Participant messages identify the participant; platform events and tool
  responses have explicit content types. Retained the agreed two-field model
  decision. Completed spoken history is distinct from generated decisions.
- Added the exact x -> x/y request examples: only the latest message has the
  current `pending_tool_calls` list, explicitly [] when empty. It is a request
  overlay, excluded from durable history, compaction and old messages. Refresh
  for every model round and remove the prior system-level pending projection.
- Pending lists describe application-managed calls only. Source inspection of
  PendingInvocation revealed running, terminal_queued and completion_admitted;
  the latter two cannot be projected as running under the user's requirement.
- Completed results are retained once in history and removed from pending in a
  consistent snapshot. Preserved native tool protocol and the distinction between
  initial submission acknowledgment and eventual outcome. Snapshot failures are
  errors, not fabricated empty lists.
- Added one owning task for the pending overlay and strengthened tool/history
  acceptance. The combined plan now has 77 pending tasks in six checkpoints.
  Superseded the initial draft and paused its review before requesting review of
  the simpler files from the already authorized Astra xhigh reviewer.

## Verification

- Documentation checks passed for 16 Markdown files, 247 local links, 48 heading
  anchors and six JSON examples. Explicit example checks verify latest-only
  pending fields, empty pending on completion, no exposed turn/version/event
  machinery and exactly two output fields. Balanced fences/whitespace and
  `git diff --check` passed.
- Independent Astra xhigh review of the simplified contract found no material
  findings. It confirmed request overlays, retained results, native tool protocol,
  internal turn state, existing voice contracts and complete task ownership.
- All 77 tasks remain unchecked in A–F (12/4/21/12/17/11); superseded files have
  no pending lists. Index remains 64 active, 50 complete, 14 pending. Historical
  Scribe evidence remains verbatim unchanged.
- No runtime changes, deployment, model artifacts, live-provider requests or
  commits. No runtime/provider acceptance is inferred from this design review.
