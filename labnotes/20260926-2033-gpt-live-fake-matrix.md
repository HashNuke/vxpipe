# GPT-Live fake-socket acceptance matrix

Date: 2026-09-26. Starting revision: `f272b9af`.

## Work and evidence

- Added JSON-line capability fixtures for caller and agent fragments, voice and
  delegated-backend usage, the documented close reasons, and malformed or
  unknown messages. PCM remains synthesized in tests so its 20 ms frames and
  silence can be checked without opaque base64 fixture blobs.
- The real STS capability now has local fake-socket proofs for provider-owned
  overlap followed by self-yield, policy-discarded output, both ordinary close
  reasons, moderation, expiry reseed, connection loss, and malformed/unknown
  event failure. Existing capability tests cover two spoken bursts, tool-call
  deduplication and pending-result ordering, failed/incomplete delegations,
  voice/backend usage identities and room-published reseed history.
- Added a regression for a delegated function call arriving after its original
  response context was retired by a new input. It failed red: the adapter sent
  the late call under the newest input context, so the capability accepted it
  and did not answer the old delegation. `GPTLiveDelegation` now stores the
  context at `session.delegation.created` and carries it with its tool-call
  action. The channel discards the retired call; the adapter responds with
  `no_longer_permitted` and sends one continuation. The focused regression and
  existing delegation tests passed green.
- The GPT-Live fake-socket, session and delegation files passed 35 tests with
  zero failures. A root run exposed a race in the failed/incomplete delegation
  test: the transport's asynchronous fixture delivery could still be queued
  when the test checked the provider. The fixture helper now uses the fake
  transport's synchronous delivery acknowledgement before the provider state
  barrier. The same acknowledgement now precedes the policy-discard assertion,
  so that test observes a processed audio burst. The focused fake-socket file
  passed 13 tests with seed `963322` after these corrections.

## Verification

- Passed from umbrella root: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix deps.unlock --check-unused`, and `bin/verify-lean`.
- The first umbrella run found only the timing race above in CallEngine; its
  other applications passed. After correcting the fixture acknowledgement, a
  fresh `PGHOST=/var/run/postgresql mix test` run passed 2,840 tests with zero
  failures and 59 tagged exclusions. `mix format --check-formatted` passed
  again after the test correction.
