# MCP results and document inspection

Status: deferred for later review (R24). Storing a response is approved; a general
result-to-model or document/media inspection feature is not implemented or approved.

## Current boundary

Store received MCP responses with the invocation, including structured content
and attachment/resource descriptors, under the complete observed tool-history
contract. Preserve reported success/error facts and unknown outcomes. An
uninspected document is not proof that the remote business action failed.

The agent decides its next steps, including whether to inspect a returned file
through a tool it is authorized to use. This does not promise an existing reader
for arbitrary files/media, add permissions, or fetch/play attachments automatically.
Saving a received descriptor is not downloading its linked content. Credentials
and authorization headers stay excluded; client visibility and whole-call
retention keep their existing boundaries.

For example, a report tool returns success and a document descriptor. Save that
observed response. The agent may request a permitted inspection tool if available;
otherwise it must not claim to have read the report. Do not downgrade the reported
business success simply because no reader supports that document.

## Questions to revisit

- How should text, structured data, embedded resources, file references, and
  media be projected into each model provider without implying unsupported
  content was understood?
- Which document/resource inspection tools should exist, and who grants them?
  What credentials, URI/network boundaries, access checks, size limits, and
  content handling would an explicitly requested fetch require?
- How should output schemas, malformed results, unsupported content, and
  partial inspection be represented without overwriting the original observation?
- How should model budgets, caching, private storage, and client projections
  handle large responses or separately fetched artifacts?
- How should result-derived instructions remain untrusted data, and how should
  the agent distinguish remote action status from inspection status?

These are future decisions, not a text/JSON-only result policy, automatic reader,
attachment fetcher, playback feature, or new output-normalization schema.

## Future verification

Use synthetic text/structured results and document/resource descriptors. Prove
the observed response is retained independently of browser visibility, references
cause no implicit network request, and an agent cannot inspect content without
an authorized supported tool. Test success plus unsupported inspection separately
from remote errors and unknown timeouts. Runtime implementation remains future.

The protocol supports structured results and heterogeneous content including
resource links; that does not supply Vxpipe's model projection or inspection
policy. [MCP tool results](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

Related: [call-definition design](../../labnotes/20260905-0405-call-definition-design.md),
[architecture](../architecture.md), and
[gap review](../call-definition-gap-review.md).
