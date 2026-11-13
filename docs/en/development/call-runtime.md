---
title: Call runtime and lifecycle
description: Compilation, admission, readiness, transfers, media policy and durable shutdown.
sidebar:
  order: 3
---

## Compile and prepare

Calls authoring validates source through Call Engine's typed compiler, checks
referenced credentials/services and writes an immutable revision. Publication
updates routes atomically. Preparation revalidates current authority and pins
the chosen revision, participants, variable schemas, service identities and
selected MCP descriptors.

Plans contain safe identities, not provider secrets or executable user-selected
modules. Activation resolves private credentials again. Editing a published spec
does not rewrite prepared plans or running calls. Numeric-string call-spec IDs
identify records; tenant scope and actor permissions still authorize every access.

## Admission and room identity

A room incarnation distinguishes one runtime instance from later instances with
the same logical room identity. Commands that can stop or replace work must
compare the exact incarnation inside the owning serialized operation.

Managed browser, incoming and outgoing startup uses an owner-monitored admission
gate. Start the room held, bind its incarnation durably, record the required
cleanup ownership, then release permitted startup. Cancellation and binding are
ordered by the call-row transaction. A cancellation that wins before release
must not permit later initialization to reopen the call.

Incoming telephony admission stores the provider-reported `from` and `to`
addresses on the call, separately from the immutable routing plan. Dedicated
`caller_id_number`, `caller_id_name` and `caller_sip_uri` columns preserve caller
identity without conflating a phone number, display name and SIP endpoint.
Only an E.164 source populates the numeric caller ID; display names never do.
SIP addresses retain their user and parameters, with an explicit `sip:` or
`sips:` scheme and normalized host. Missing identities remain null. These are
reported identities, not proof of ownership. Call inspection displays the caller
ID and SIP address separately, including SIP-only calls without a numeric ID.
A receive connection's configured number is the destination and must never be
used as a caller fallback. Older calls without a captured caller address leave
that identity unavailable unless independently recovered from a matching carrier
record.

Join tokens are scoped, expiring and single-use. Token issuance/redemption and
call cancellation share the established lock order. A human transfer destination
may obtain a later admission after the exact failed admission is released; old
tokens remain consumed in history. A stale release cannot clear a replacement
admission. An uncertain persistence result stays closed. Abrupt node loss does
not imply an admission was safely released.

Outgoing call creation has a tenant-scoped idempotency key and request digest.
An accepted dial submission, answered event and media connection are separate
facts. An uncertain submission is retained rather than automatically redialed.
Authenticated carrier events select the initialized leg, service and incarnation;
they cannot create a replacement room during cleanup.

## Readiness

Readiness descriptors identify the capability, exact owner/binding generation,
effective configuration, policy interval and probe adapter. A PID or successful
`start_link` is not evidence that a provider, media sink or required recording
writer can accept work.

Collectors probe asynchronously and keep a bounded attempt deadline. Owner
notifications trigger another probe; they carry no authoritative ready status.
A poll remains a fallback. A notification during an active probe schedules a
fresh probe rather than accepting stale evidence.

At admission and handoff, recheck the prospective resource inventory. A new
listener, replacement session or changed permission can invalidate an earlier
ready report. Retain unaffected resources and the original deadline while
preparing the changed set. Never block RoomAuthority on DNS, provider startup,
database access or audio generation.

## Media policy and privacy intervals

Membership revisions order room policy changes. Each media path also carries a
permission interval that changes only when its relevant rules change:

| Path | Boundary that matters |
| --- | --- |
| STT and transcript ingress | Source presence, recognition demand, transcript routes/storage. |
| Audio normalization | Source presence, outgoing audio routes and recording permission. |
| Output | Recipient presence and incoming audio routes. |
| Recording | Recording permission and permitted queued media. |

Unrelated membership changes do not restart every recognizer or clear every
output. Restricting then restoring a permission creates a fresh interval, so old
buffered data cannot reappear after relaxation. Mixer/transcript routing still
checks current presence.

Private transfer resources track each intervening policy transition while they
are prepared. Jumping directly from an old revision to a later one cannot prove
that no privacy boundary occurred. Adoption changes authority over prepared
resources; it does not reparent an OTP subtree.

## Transfers, openings and waiting

A transfer is an attempt-scoped transition: validate an allowed destination,
prepare its resources, privately brief/accept where required, commit policy,
acknowledge output clearing/cues, then release conversation. New listeners join
the same readiness and cue ordering before receiving conversation.

Before adoption, destination failure can recover the source using retained
resources. After a required resource has been adopted or release has partly
occurred, the runtime may have to close the room to preserve policy. RoomAuthority
owns terminal transfer facts before its stop result tears down the incarnation.
Competing supervisor shutdown paths must not erase required failure evidence.

Opening audio is an independent room-owned operation, including when the initial
receiver is human. Waiting pauses and queued output clears before the opening
is released. Protected openings remain uninterruptible through actual sink
completion. Readiness is checked again before conversational release.

## Whole-call shutdown

HTTP, MCP and platform hangup enter the same authorized workflow. It commits
`hangup_requested_at` before runtime cleanup. An unused prepared call can end
atomically; an active call reports `ending` until terminal evidence is durable.

Gateway reconciliation uses bounded work and retains exact ownership after a
requester timeout or restart. It never recreates a room or dials a carrier to
resolve uncertainty. Room shutdown, carrier termination, command-worker drainage
and required persistence acknowledgements are distinct evidence. Unknown or lost
membership cannot be reported as confirmed cleanup.

Managed calls become durably ended once both the room's archived closure and
the gateway cleanup acknowledgement are saved, in either order. The carrier leg
owns carrier termination, command drainage and final usage persistence. Local
media and WebSocket roots separately prove their own orderly shutdown.

Handled WebSocket failures retain their protocol error close codes while using
the normal WebSock stop path. This allows the actual socket owner to finish an
orderly shutdown without classifying a handled media error as unknown cleanup.
Unexpected crashes and lost ownership remain unconfirmed.

Use links, monitors and explicit lifecycle operations for correctness.
`terminate/2` supplies best-effort cleanup only. A late callback, completion or
timer must match the original incarnation/attempt/generation, and cannot stop a
new owner found through a broad logical-name lookup.

## Verification boundaries

Exercise admission/cancellation races, stale incarnation commands, partial
readiness, private handoff, destination recovery and caller/carrier hangup at
their owning boundaries. Native WebRTC and controlled carrier tests verify
transport composition; real carrier audibility remains a separate live gate.
The transfer wait-sound milestone still retains its explicitly open acceptance
items. See [Testing and verification](testing.md) and the
[milestone index](../../../labnotes/milestones/index.md).
