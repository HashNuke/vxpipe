# Durable outbound MCP OAuth storage

Persistence owns encrypted attempts, one-time claims and fenced token replacement.
Calls owns current browser authorization; Console owns protocol orchestration.
These repository operations are trusted internal ports, not public APIs. Network
requests run outside transactions. Production UI and independent-node acceptance
remain [milestone gates](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

## Attempts

`OAuthAttemptStore.issue` locks the tenant row before enforcing a maximum of eight
live unclaimed attempts. State is stored as a SHA-256 digest. Attempt identity,
operation, target connection generation, user/session, installation revision,
issuer, callback, resource, draft revision and optional return context are retained
for the caller. The envelope uses the installation keyring with tenant/attempt ID
and an attempt-specific encryption purpose.

The encrypted payload authenticates the complete binding, state digest and expiry
as canonical Unix microseconds. Claim compares those copies to the selected row
before consuming it. Updating cleartext binding, digest or lifetime columns cannot
produce a valid claimed payload. Expiry must initially be within ten minutes;
equality at the deadline is expired.

`locate` resolves a live state's tenant only for its bound user/session. It does not
consume state or replace caller authorization. `claim` locks the attempt row,
requires current authority values and unexpired/unclaimed state, decrypts and
checks the authenticated metadata, then erases ciphertext/key ID atomically while
marking it claimed. A private snapshot carries secrets to the caller. Missing keys
leave the attempt unconsumed so a repaired keyring can recover it.

## Grant replacement

`OAuthGrantStore` serializes refresh on the connected tenant/connection row. A claim
is bound to configuration generation and current grant revision and lasts thirty
seconds. Concurrent claims cannot redeem the same refresh token. Expired, failed
or ambiguous claims require reconnect; they are never reclaimed for another
exchange. Client-credentials grants use the same claim fencing without refresh
tokens.

Successful completion requires the same live claim and generation. It updates only
validated token fields, increments grant revision and preserves configuration
generation, client identity and credentials. An omitted refresh token or scope
retains its saved value. An omitted access-token expiry clears the previous expiry,
because that timestamp described the old token. Invalid completion rolls back
without consuming the claim. Disconnect or replacement fences late completion.

Credential re-encryption preserves a live claim and both revisions. Completion
uses the configured current key. Static catalog refresh does not overwrite the
encrypted grant. All resolved snapshots use opaque inspection.

## Availability

The shared MCP repository boundary maps known Repo/DBConnection/Postgrex outages
and checkout exits to fixed errors. OAuth stores return
`mcp_oauth_storage_unavailable`; existing connection operations retain
`mcp_connections_unavailable`. Unrelated programmer exceptions remain exceptions.
An outage cannot be reported as successful consumption or token rotation.

## Retention and key retirement

Run these commands from the umbrella root using the configured installation
keyring; no credential values belong in command arguments:

```sh
mix vxpipe.mcp_credential.reencrypt --batch-size 100
mix vxpipe.mcp_oauth.prune --batch-size 100
```

Each operation processes one batch of 1–500 rows. Re-encryption handles connected
MCP credential/grant envelopes. Pruning deletes expired or claimed attempts without
decryption, skips locked rows and reports terminal rows remaining plus live
`pending_by_key` counts. Schedule pruning periodically. A zero processed count may
mean rows were locked; use remaining counts and repeat.

Install the new decrypt key on every reader, then switch every writer. Run provider
and MCP re-encryption until all old-key connection rows are gone. Retain old keys
for live attempts until claimed or expired, and inspect pending counts after every
writer has switched. No single store's empty result proves a key is safe to retire.
See the [operator transition](../platform-credential-reencryption.md#operator-transition).

## Decisions and verification

Expired refresh claims cannot be retried because a provider may already have
rotated the token. Configuration generation and grant revision remain separate so
refresh does not invalidate a user's unchanged configuration. Attempt expiry and
state were added to the authenticated payload after tamper regressions demonstrated
that cleartext columns alone allowed lifetime/state substitution.

Focused tests cover encryption, one-time claim, admission bounds, authority binding,
tampering, missing keys, key transitions, retained claims during rotation, rollback,
wrong-tenant operations, outage recovery and redacted operator output. Seven tagged
persistence tests now use independent BEAM processes and distinct PostgreSQL backend
connections for claim/admission/refresh/revoke races, claim cleanup and claimant
death. See [cross-node evidence](../../labnotes/20261107-0959-mcp-cross-node.md).
Independent-node token/transport renewal has its own Console lane; re-encryption
during cross-node refresh and old-key retirement remain separate acceptance gates.
Earlier storage evidence and review remain in the
[checkpoint labnotes](../../labnotes/20261107-0132-review-mcp-oauth-storage.md).
