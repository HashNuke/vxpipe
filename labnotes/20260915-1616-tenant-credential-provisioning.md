# Tenant credential provisioning

## Scope and decisions

- First coherent implementation commit within tenant-provider checkpoint 1: encrypted Google/
  Deepgram provisioning, metadata listing, local auth validation, a Calls repository port and
  explicit runtime encryption keys. Live calls do not use the new store yet. Keep the milestone
  and checkpoint unchecked until inline save/publish/prepare/voice activation are delivered.
- `env.sample` is deliberately visible, with no leading dot. It catalogs current platform settings,
  required key placeholders and commented optional variables. `.env.example` points to it during
  the existing development-flow transition; final aliases/global-provider removal belong to the
  owning cutover work. No `vxpipe_config` application or platform TOML loader is reintroduced.
- User review removed `VXPIPE_DEV_SPEECH_PROFILE` from `env.sample`: speech profiles are obsolete
  in the target design and should not be advertised in the new sample. The existing development
  runtime reader still needs removal with checkpoint 1's call-flow cutover; the current operator
  transition is documented explicitly rather than claiming the reader is already gone.
- Added the user's explicit checkpoint-1 task to delete the actual speech-profile runtime lookup,
  both switch branches and obsolete references, with a negative test for the retired variable.
  Also recorded their final shared-bucket names: `STORAGE_BUCKET`, `AWS_REGION`, `AWS_ENDPOINT`,
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and optional `AWS_SESSION_TOKEN`, replacing the
  initially suggested VXPIPE-prefixed names and removing both old destination families. Implement that as the next separate
  configuration commit; do not represent the current separate settings as the approved final API.
- Use OTP AES-256-GCM, authenticated tenant/binding/version identity, an externally provided
  versioned keyring, no default key, no provider environment fallback and no new dependency.
  Record durable format, implications and rejected alternatives in `docs/provider-credential-storage.md`.
- Provider auth is closed to Google/Deepgram API-key payloads in this chunk. Operations are trusted
  host workflows, not unauthenticated management APIs. Existing Vxpipe API-key hashing is unchanged.

## Red, green and refactor

- Initial six PostgreSQL contract tests failed on the missing keyring/store; implementing the
  minimum coherent port/schema/cipher/adapter made those and the three existing API-key tests pass.
- A separately added query telemetry test failed: `log: false` still allowed Ecto's telemetry
  subscriber to observe bound values/results. Credential queries now also set `telemetry_event: nil`.
- Added runtime key-config and Mix task tests before implementation; they failed on missing
  runtime repository injection/tasks. Invalid configuration and CLI errors contain safe reasons
  only, and metadata listing needs no decryption key.
- Initial `IO.binread/2` failed under ExUnit StringIO on installed Elixir 1.19.5/OTP 28 because
  OTP's file read protocol supplied an atom prompt. A direct `:io.request` worked, but final
  refactoring uses ordinary Elixir `IO.read/2` with a bounded character count and explicit byte
  limit. Only terminal detection needs `:io.getopts/1`; Elixir exposes no terminal-query wrapper.
- User asked why Erlang IO was needed. Checked installed Elixir IO and official OTP protocol:
  `stdin` indicates terminal input; `terminal` aliases stdout. PTY stdout with redirected stdin
  must remain accepted. Refactored tenant validation to remove a dummy Google binding in listing.
- Focused new suites after refactoring: 16 tests, 0 failures, seed 42614. Logs under ignored
  `tmp/credential-*-red.log`, `tmp/credential-review-green.log` and `tmp/credential-refactor-green.log`.

## Independent implementation review

Requested GPT 6 Astra at xhigh reasoning, independent read-only review of this bounded chunk.
The review found three issues: terminal input could echo secrets, leading-dash tenant keys failed
CLI parsing, and an absent Repo raised instead of returning the unavailable error.

Wrote focused regressions first: 12 tests, 3 expected failures, seed 37155. Fixed the CLI input
policy and safe argument normalization. The store now recognizes the exact Ecto lookup and
DBConnection checkout failure boundaries, preserving unrelated programming exceptions. Expanded
the outage case to a supervised Repo termination using both its name and stale pid, then verified
access through the recovered repository. All 16 focused tests passed after the fixes. Independent re-review found no remaining findings,
including its own terminal, leading-dash and absent-Repo reproductions.

## Acceptance and completion checks

- Disposable PostgreSQL acceptance passed: create/migrate, bootstrap tenant, provision both
  providers through JSON stdin, and list metadata in fresh Mix VMs. A further fresh VM resolved
  both persisted payloads correctly. Removing encryption variables preserved listing and caused
  resolution to return `credential_key_unavailable`. The owned disposable database was dropped.
- Real PTY acceptance passed: interactive stdin exits before requesting input; piped stdin with
  terminal stdout succeeds without printing the synthetic payload. The regression suite separately
  asserts that no input request reaches an echoing terminal device.
- Manual harness and output are ignored under `tmp/credential-provisioning-acceptance.py` and
  `tmp/credential-provisioning-acceptance.log`; no real upstream request or credential was used.
- Full persistence suite passed: 65 tests, 0 failures (seed 350984).
- Root format, warnings-as-errors compilation, strict Credo and unused-lock checks passed after
  independent re-review. Full root `mix test --preload-modules --max-requires 1 --seed 235296
  --max-cases 4` completed: **1,452 tests, 1 failure, 16 exclusions**. The failure was the existing
  Gateway `native repeated AI transfers retain callers and recordings across listener re-entry`
  case: listener Morse decoding returned `invalid_timing` at the final flush.
- The exact Gateway test passed in isolation with unchanged source and the same preloading,
  seed and concurrency: **1 test, 0 failures, 67 excluded**, 112.8 seconds. Logs:
  `tmp/credential-gate-test.log` and `tmp/credential-native-isolated.log`. This is evidence of an
  intermittent native lane failure, not a passing full umbrella run or a proven fix.
- Independent diagnosis found no evidence connecting this failure to provisioning. The existing
  audio assertion consumes RTP without continuity checks and omits decoder state at timeout;
  packet timing/loss remains a hypothesis. Preserve this unresolved acceptance issue for the
  next full run; do not weaken the assertion or increase timeouts without evidence.
- Documentation verification found all 137 relative file targets; checked the visible sample
  filename, two required key placeholders and commented optional settings. `git diff --check` passed.
- Separate specification review approved the speech-profile deletion task's ordering and added
  missing/blank/invalid/retired-only bucket cases and enablement preservation to the shared bucket task.
  The final naming is the user's `STORAGE_BUCKET` plus AWS settings, superseding their first naming
  suggestion. These remain future implementation tasks, not checked implementation claims.


## Next call-flow work

The current parser takes profile strings and `DefinitionCompiler` requires `capability_profiles`.
`Definitions.save` records compiler support errors as draft metadata; publication checks those
stored errors, and `PreparedCallFactory` recompiles before audio preparation. The next coherent
change needs the inline selection parser/catalog and fresh credential gates together with initial
activation, while migrating shared consumers and fixture definitions. A local-only schema change
would not complete the specified runnable flow. Preserve engine/Calls/Persistence dependency direction
through an injected credential-source boundary.

While inspecting the prior native timeout log, observed that the existing STT process crash state
includes provider authorization headers (the test uses synthetic material). Connecting tenant
credentials to STT must also prevent those values appearing in process error reports. No real
provider request or secret was used in the storage acceptance.
