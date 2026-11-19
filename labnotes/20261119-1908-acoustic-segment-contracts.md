# Acoustic segment contracts

## Decision and implementation

The durable version-1 acoustic segment records already exist, but the Console
presenter omitted them and its client decoder ignored them. Extend the existing
session-authorized report/turn endpoints additively: run.unattached_segments and
turn.acoustic_segments. Keep the outer schema version and existing authorization,
source/clock identity, timing precision and nullable response fields.

Shared core types expose the corresponding optional nullable evidence fields.
Console normalizes legacy absent/null fields to null; an explicit version-1 empty
collection remains distinct. Preserve segment epoch, sample positions, estimated
and confirmed boundary times, uncertainty, reasons and omitted count. The decoder
checks the durable version-1 count/offset bounds, boundary completeness/order and
per-epoch non-overlap; malformed evidence fails only the diagnostic loader's existing
error boundary. No audio or transcript payload is added.

This checkpoint changes the authorized data contract, not the rendered view. Both
hosts' segment/participant fixtures and rendered-browser acceptance remain open.
The existing collapsed interface continues to render legacy reports unchanged.

## Red/green evidence

Before implementation, the two new endpoint tests fail because the segment keys
are absent (`/tmp/vxpipe-segment-api-red.log`); three new client tests fail because
the decoder silently ignores evidence (`/tmp/vxpipe-segment-client-red.log`).
After implementation: endpoint selection 10/10 and client selection 11/11.
Endpoint tests cover both route aliases, legacy null, precision/provenance and
existing session, bearer, permission and tenant denials. Client tests distinguish
zero/empty from unavailable, preserve partial/unmapped boundaries, and reject
unsupported versions, over-limit counts, invalid offsets and contradictory segments.
Independent Astra review is clean. Its backend/decoder parity probe checks 8,307
evidence cases (514 backend-valid) through both report and turn decoding, with
identical acceptance and exact camelCase preservation. Evidence includes null/zero
boundaries, incomplete mappings, confirmations, count limits and per-epoch overlap
and duplicates (`/tmp/vxpipe-segment-contract-review.log`). Independent endpoint and
client reruns also pass 10/10 and 11/11.

Root format, compile with warnings as errors, strict Credo and unused-lock checks
pass. Core build, root workspace build/typecheck, Console typecheck and focused
client lint pass. The existing core/React latency selections pass 26/26. Documentation
links and git diff --check pass. No speech-state change requires Lean verification;
no live provider, deployment or full umbrella test run occurred.
