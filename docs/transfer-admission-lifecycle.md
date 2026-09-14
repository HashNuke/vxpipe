# Transfer destination admission lifecycle

A failed private transfer connection must not permanently consume the destination's place in a
running call. Keep every consumed token and admission in history, but distinguish released
admissions from active ones. A partial unique index permits only one active admission per
call/participant; token consumption remains atomic and single-use. Releasing an admission matches
its tenant, call, participant and exact token, and is idempotent. A late release cannot clear a
newer admission. Existing rows remain active on migration; do not infer that they disconnected.

Gateway owns the destination session from issuance through connection shutdown. Its existing
session process tracks the claimant and the connection incarnation. Expiry before a connection,
startup failure, claimant loss before binding, and connection termination release that exact
admission. A live bound connection outlives the credential's claim TTL. Failed persistence release
stays closed to further admission and is retried; never reopen on an uncertain database result.
The runtime still authorizes the current transfer attempt and enforces private media/acceptance.
This does not introduce a UI retry bypass, an automatic redial or a new call-definition field.

Rejected alternatives: deleting the admission loses history; allowing unrestricted simultaneous
claims weakens admission exclusion; checking only room process existence races connection startup;
releasing from a connection's `terminate/2` misses abrupt failure. Reuse the Gateway session's
lifecycle and monitors instead of creating another transfer coordinator.

The migration preserves historical rows. Reversing the partial index to its former uniqueness
requires that no participant has multiple historical admissions; it must not delete those rows to
make rollback succeed. Old active reservations are not retroactively reclaimed by this migration.

Verification covers exact/stale release, retained history and token single-use at persistence,
existing concurrent claims, five Gateway session lifetime cases and the actual WebRTC recovery flow
through another briefing and accepted handoff. The rendered sample completed a later transfer in
the original call with live providers, cues, bidirectional audio and final support/caller transcripts.
See the [readmission labnote](../labnotes/20260914-1929-transfer-desk-readmission.md) for evidence and
failed attempts; complete transfer milestone acceptance remains open.

Abrupt loss of the owning Gateway node or the session process itself leaves its reservation closed;
this change does not add a durable crash-reclamation worker. Migration does not reopen old admissions.
