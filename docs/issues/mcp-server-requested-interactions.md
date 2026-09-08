# MCP server-requested interactions

Status: deferred for later review (R25). Sampling, elicitation, and related
server-driven interactions are not initial-slice features.

## Current boundary

The initial remote client does not advertise unimplemented capabilities or gain
authority from a server request. Report missing capabilities clearly without
silently invoking models, prompting a participant, granting access, or claiming
the requested interaction completed. Ordinary agent conversation is unchanged.

The selected Jido MCP integration profile is `2025-11-25`, where sampling and
elicitation use server-initiated requests and negotiated client capabilities.
Neither is enabled merely because the SDK offers it. This supersedes this issue's
earlier `2026-07-28` input-request/MRTR assumption; support for that revision is
not part of the initial integration.
[MCP elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation),
[MCP sampling](https://modelcontextprotocol.io/specification/2025-11-25/client/sampling).

Receiving a request for an unsupported interaction does not approve performing it
or resubmitting the originating tool call. Keep the observed request/outcome,
distinguish an incomplete interaction from business success, and preserve the
executor's no-automatic-retry policy. A future request/response implementation
must explicitly define lifecycle and authorization rather than acquire them
implicitly from a remote server.

For example, a remote report tool requests another model generation or asks the
user for information before it can finish. The initial adapter does not advertise
that facility or perform it silently. The agent can still talk normally, but that
conversation is not an implemented MCP elicitation response.

## Questions to revisit

- Which interactions/capabilities should be supported and negotiated, and at
  what application, tenant, call, or agent authorization boundary?
- Who chooses a sampling model and pays for it? What instructions, data access,
  tool permissions, cost limits, and observability apply?
- How should elicitation reach the correct participant, present information,
  collect input, and distinguish acceptance, refusal, and cancellation?
- How should server-request identity, response state, deadlines, duplicate side
  effects, and the originating tool invocation's history relate?
- What happens on speech interruption, transfer, shutdown, timeout, or explicit
  cancellation without inventing a rollback guarantee?
- Which related server-driven features require distinct grants and safe failure
  behavior, instead of acquiring ambient authority?

No user-interaction UI, sampling adapter, continuation worker, automatic retry,
or new call-definition fields are approved by this issue.

## Future verification

Before adding support, use controlled servers to test advertised capabilities,
authorized and unauthorized server requests, model-cost attribution, request/response
identity, and lifecycle failures. Initially verify that unsupported capabilities
are not advertised, produce clear missing-capability outcomes, and cause no
unauthorized model request or participant interaction. No runtime tests here.

Related: [call-definition design](../../labnotes/20260905-0405-call-definition-design.md),
[architecture](../architecture.md), [gap review](../call-definition-gap-review.md),
and [automatic tool retry issue](automatic-tool-retries-and-idempotency.md).
