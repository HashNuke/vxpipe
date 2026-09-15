# Model-context compaction

Status: production selection, accounting, Agent Runtime integration, Call
Engine activation wiring, and private usage projection implemented. Controlled
provider-native fallback verification and configured-profile wiring are
complete; the credentialed interoperability run remains external evidence.

## Decision

Context compaction uses the active agent activation's already pinned model
provider, model, credential, and provider-native routing options. It does not
select a cheaper model, a local model, another configured profile, or a new data
recipient. The summary request is buffered and tool-less even when ordinary
conversation uses streaming.

Selected historical messages are encoded as JSON data beneath one fixed
summary-only system instruction. The compactor receives no model-visible tools,
pending-invocation projection, Call Variables projection, executor binding, MCP
binding, or permission state. A response containing a tool call is invalid. The
accepted output becomes an assistant-role `:derived_summary` message with a
fixed untrusted-data envelope; it is never inserted as a system message or tool
result.

This selection keeps the authorized model recipient unchanged. A configured
provider/router may still choose an upstream according to its explicitly
accepted native policy; that is part of the pinned provider configuration, not
a fallback decision made by Vxpipe.

## Accounting and limits

ReqLLM 1.22 exposes catalog context/output limits and final provider usage, but
does not expose one exact local input tokenizer for every supported provider.
Vxpipe therefore uses these concrete rules:

- Context-window capacity comes from the pinned ReqLLM model's
  `LLMDB.Model.limits.context`. A model without a known positive limit cannot
  enable automatic compaction unless a later explicitly validated model profile
  supplies one; Vxpipe does not guess a capacity.
- Output reserve is the effective positive maximum-output option validated by
  ReqLLM, including its catalog default when the configured request omits one.
- Input measurement encodes all model-visible normalized fields—messages and
  tool-call relationships, tool definitions/schemas, pending invocation state,
  and transient authorized model context—and charges one accounting token per
  encoded UTF-8 byte. It then adds 256 base units, 32 per message, and 64 per
  tool for provider envelope overhead.
- This is a deliberately conservative cross-provider estimate, not a claim of
  exact tokenizer parity. The 75% trigger leaves another 25% safety margin. A
  provider may still reject a request when its private tokenizer or framing
  differs; that remains a bounded provider failure, never permission to delete
  protected input.
- One compaction attempt receives only the token allowance left by the strict
  below-50% target. If protected content already prevents that target, the
  attempt may use only the remaining usable window. Protected content filling
  that window fails before a summary request.
- Summary text has an independent 256 KiB structural bound and is remeasured in
  the complete rebuilt request. One failed, timed-out, malformed, tool-calling,
  or still-oversized result is rejected without recursively compacting or
  changing the original conversation.
- Local counting is bounded to 1 second. Production summary work is bounded to
  15 seconds and also remains inside the owning conversational request deadline.
  Four recent committed conversation entries remain protected by default.

The derived summary stays inside the owning Agent Runtime Session and its model
requests. It is never emitted as a runtime event, archive fact, client event, or
replacement transcript. Consequently, permitted original transcript facts stay
unchanged and a transcript-storage denial cannot be bypassed by persisting
derived prose. Source correlations remain attached to the in-memory derived
entry for safe snapshot replacement, not publication.

Observed compaction usage and bounded provider/model identifiers follow the
existing private usage path without the summary or its source messages. Each
summary request is a separate model attempt attributed to the real turn that
triggered it; component names use the `context_compaction_` prefix, so no fake
user turn is invented and conversation usage remains distinct. A rejected
summary retains known incurred usage with a failed outcome. An attempted
compaction with no reported measurement still records a failed
`context_compaction_operation`; failures before a model attempt record nothing.

## Provider-native fallback

ReqLLM generation options are validated against the selected provider at
configuration time with unsupported-option handling forced to `:error`. A
native routing/fallback object accepted by a provider such as Zenmux passes
through unchanged. The same object presented to a provider that does not expose
that option is rejected before network I/O.

The credential cutover replaces capability profiles and application-level provider
settings with [inline selections](inline-provider-selections.md) and tenant DB
credentials. The current inline catalog supports Google model inference. Zenmux
native routing remains implemented and tested in the internal ReqLLM adapter;
its inline selection and tenant-credential migration are still pending in
[checkpoint 5](milestones/tenant-provider-credentials-and-platform-configuration.md#checkpoint-5--preserve-existing-provider-credential-integrations).

The pre-cutover Engine activation test verified `zenmux:openai/gpt-5`, nested
`provider_options.provider` routing data and ordinary generation options. The
inline migration must preserve that existing contract while rejecting executable
hooks and protected transport/authentication fields. `openai` and `anthropic`
inside that routing data are Zenmux destinations; they do not require separate
Vxpipe credentials. The [provider inventory](existing-provider-credentials.md)
records the source evidence and current migration limits.

Vxpipe does not define a fallback list, retry coordinator, alternate credential
selector, or cross-provider replay policy. Native routing does not resubmit MCP
work, restart a partially emitted conversational stream, or replay TTS.

A controlled ReqLLM/Zenmux adapter test observes the encoded HTTP request. It
proves that one request contains the selected model, native routing/fallback
object, and exact tool JSON Schema while omitting private Vxpipe executor data.
The response projection retains the provider-reported actual model and usage.
At the Session boundary, a separate partial-stream failure test proves there is
no hidden Vxpipe model resubmission, buffered fallback, or tool submission after
text has been emitted.

The tagged live lane requires `ZENMUX_API_KEY` and optionally accepts
`VXPIPE_ZENMUX_MODEL`; it is excluded from the default suite. It verifies a real
Zenmux request with native routing and an exact tool schema, then requires a
non-empty provider-reported model and usage. The lane is present and compiles,
but has not been executed in this workspace because the credential is unset.

## Alternatives rejected

- A dedicated cheaper summarizer would introduce a new recipient and model
  policy that has not been authorized.
- Exact tokenizer libraries selected by provider name would create a partial and
  drifting compatibility matrix while still missing provider framing and newer
  models.
- Character-count approximation is not used because UTF-8 and tokenizer
  behavior make it too easy to undercount multilingual or structured input.
- Inserting the summary as a system message or preserving old tool-result roles
  would give derived prose authority it must not have.
- Recursive compaction can amplify latency and cost without guaranteeing room;
  one bounded attempt has a deterministic outcome.

## Verification evidence

Focused Agent Runtime tests prove model metadata/output-limit resolution,
unsupported native-option rejection, supported routing pass-through,
conservative measurement of every normalized input class, correlation exclusion,
UTF-8 handling, tool-less JSON summary projection, pinned provider reuse, output
cap projection, successful and rejected usage preservation, rejection of summary
tool calls, safe Session commit ordering, and compactor termination with its
Session. Call Engine passes the application compaction setting into each
activation; a room test proves that an explicitly queued caller turn waits for
compaction and then sees the committed summary. The same room/archive boundary
retains original permitted input/output facts, stores separately named
compaction usage, and never stores the derived summary. Immediate caller input
still uses the existing interruption semantics. Tagged provider interoperability
now has a separately excluded Zenmux lane. Controlled adapter and partial-stream
failure coverage pass, and Call Engine tests prove profile-over-application
generation-option precedence plus unsupported-combination rejection. The
credentialed request remains external evidence.
