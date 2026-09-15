# Shared artifact bucket

## Requested contract

- The user requested one bucket for recordings and call-details JSON. Their final variable names
  are `STORAGE_BUCKET`, `AWS_REGION`, `AWS_ENDPOINT`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
  and optional `AWS_SESSION_TOKEN`; this supersedes their earlier VXPIPE-prefixed suggestion.
- Delete both `VXPIPE_RECORDING_S3_*` and `VXPIPE_CALL_DETAILS_S3_*` readers and fallback rules.
  Recording stays opt-in; a database plus shared bucket enables automatic call-details publication.
  Absent/blank new bucket settings cannot be rescued by retired variables. Recording configured
  without a bucket must still fail its existing configuration check.
- This is an early, separately usable configuration commit within the larger tenant-provider
  milestone. Full checkpoint 7 remains open for its database aliases, restart/call-flow and legacy
  configuration removal gates. Speech-profile reader deletion stays an explicit checkpoint-1 task.

## Implementation and evidence

- Wrote five focused Console runtime configuration tests first. All five failed for expected
  reasons: the new variables were ignored, old destinations still won, and the session-token
  mapping did not exist. Red evidence: `tmp/shared-bucket-red.log`, seed 527529.
- `config/runtime.exs` now constructs one destination setting list for recording/playback and
  document publication/recovery. Invalid active destination configuration raises only variable
  names. No old S3 variable is read by production configuration.
- Existing ExAws defaults already read the standard access-key/secret-key environment variables,
  but installed ExAws does not automatically map `AWS_SESSION_TOKEN`. Runtime adds its S3-only
  `security_token` source only when that variable is present. The config stores a system-variable
  reference, not the token value, and the absent case preserves the role credential chain.
- Checked AWS's official temporary-credentials documentation when explaining the session token
  to the user. It accompanies temporary access-key credentials and is unnecessary for ordinary
  long-lived keys. Credential acquisition/refresh remains ExAws/deployment-owned.
- New runtime and existing recording configuration tests pass: **10 tests, 0 failures**, seed
  966678. Both writers, playback and recovery share bucket/region/endpoint; cases cover recording
  disabled, absent/blank bucket, retired-only/conflicting values, unsafe endpoint and optional token.
- Updated the visible `env.sample`, synchronized the relevant `.env.example` settings, and removed
  the old names from current Console operation docs and architecture. Updated credential runtime
  tests to isolate the new platform environment settings.

## Review and final verification

Independent review found that existing endpoint parsing silently accepted malformed ports such as
`:bad` / `:-1` as port 80, and accepted out-of-range ports. Added failing boundary tests in each
owner first: documents 4 tests/1 expected failure; recording 6 tests/1 expected failure. Switched
both parsers from permissive `URI.parse/1` to Elixir `URI.new/1` and required ports 1–65535. This
uses the standard validator and preserves the existing configuration error contracts.

The same review requested migration documentation: object references retain keys, not their
original storage endpoint, so preserve current location when renaming variables; previously
separate stores require explicit consolidation with object keys preserved and stored ETags preserved
or reconciled, followed by playback verification (`If-Match` uses the stored ETag). Added this to Console
operations and architecture; no migration or old-location fallback runs automatically.

Final re-review found no remaining code findings; its ETag documentation refinement is included.
After the fix, the owning focused suites passed: 4 Artifacts tests (seed 957203) and 11 Console
configuration tests (seed 321601). The credential-runtime isolation tests also passed (2 tests).
A fresh `mix run --no-start` VM verified identical recording/playback/publication destinations
and the installed ExAws resolution of synthetic access-key, secret-key and session-token inputs;
it started no provider/object-store request. Thirty-three relative documentation targets and the
visible sample's new optional variable names were checked.

Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass after review.
The full root suite also passed: **1,459 tests, 0 failures, 16 excluded**, using
`mix test --preload-modules --max-requires 1 --seed 235296 --max-cases 4`.
Evidence is in ignored `tmp/shared-bucket-gate-{format,compile,credo,lock,test}.log` files.
The previous provisioning commit's native listener Morse timing failure did not recur. Its cause
remains unproven; no audio assertions or timeouts were changed to obtain this result.

Marked only the shared-bucket implementation task complete and synchronized the milestone/index
evidence. Full checkpoint 7 remains open, as does checkpoint 1's inline call-flow integration and
actual speech-profile reader deletion. No live S3 request or object migration was performed.
Final documentation verification checked 166 relative file targets across the changed operations,
architecture, milestone, index and labnotes files; `git diff --check` passed.
