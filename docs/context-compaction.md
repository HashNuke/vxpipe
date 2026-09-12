# Model-context compaction

Status: production selection and accounting decided; runtime integration in
progress.

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

Observed summary usage and actual provider/model metadata follow the existing
usage-event path under a compaction purpose. They are not assigned to a fake
user turn. Source conversation correlations remain on the derived entry so Call
Engine can apply the source intervals' transcript-storage permissions before an
asynchronous subscriber sees the summary. The complete permitted transcript
archive remains unchanged.

## Provider-native fallback

ReqLLM generation options are validated against the selected provider at
configuration time with unsupported-option handling forced to `:error`. A
native routing/fallback object accepted by a provider such as Zenmux passes
through unchanged. The same object presented to a provider that does not expose
that option is rejected before network I/O.

Vxpipe does not define a fallback list, retry coordinator, alternate credential
selector, or cross-provider replay policy. Native routing does not resubmit MCP
work, restart a partially emitted conversational stream, or replay TTS.

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
cap projection, usage preservation, and rejection of summary tool calls. Runtime
session integration, source-privacy publication, and tagged provider
interoperability remain milestone work.
