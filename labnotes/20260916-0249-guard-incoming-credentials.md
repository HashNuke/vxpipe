# Guard incoming credentials

## Scope and design review

- Continue checkpoint 3 from `5c82864`: put the existing active credential/reference check
  inside the incoming call/leg insertion transaction. Reuse current admission and duplicate
  recovery; no new provider, authentication mode or carrier workflow.
- Calls supplies a mandatory authorization callback through its call repository port.
  Persistence invokes it in the existing Ecto.Multi before either insertion. Credential
  repositories must share the transaction's Repo context; locks survive until its commit.
- Existing duplicate lookup and post-conflict recovery stay outside the insertion transaction.
  An already stored duplicate does not run the new-write authorization callback.
- Independent read-only design review confirmed this boundary. Propagate the callback's
  success/error directly; do not wrap an authorization error in a successful Multi result.
  Retain only an authorization marker, never private credential snapshots, in Multi changes.
- Add post-compilation credential/binding race tests before implementation, then verify real
  connection lock lifetime and concurrent duplicate recovery in the tagged integration lane.

## Red tests

- Added three post-compile failure cases plus a valid admission/duplicate/call-ID-conflict
  control. The initial model fixture used `credential` instead of `credential_name` and
  correctly failed definition validation; fixed the fixture before recording the expected red.
- Expected red: all three failure cases still admitted a call. A separate-connection test
  also acquired the service lock while call/leg insertion was paused before commit, proving
  the final guard was absent. Six focused tests: four expected failures and two controls pass.
- The second tagged check makes both requests pass duplicate preflight before insertion,
  using distinct generated call IDs. It already passes against the existing recovery boundary;
  retaining that result is a regression requirement for the new nested credential guard.

## Green implementation

- Calls now supplies its existing revision/plan credential guard as a mandatory zero-argument
  repository callback. Persistence runs it in `Multi.run(:credentials)` before call/leg writes.
  The finite memory adapter follows the same callback contract; no default bypass exists.
- The outer insertion transaction owns lock lifetime. Existing duplicate lookup and recovery
  remain in place outside it. The callback returns an authorization marker or a safe error,
  never private credential data. Repository documentation requires a shared transaction context.
- Six focused checks pass, including both real-connection integration cases. The corruption
  fixture initially used too-short ciphertext rejected by the existing database constraint;
  corrected it to invalid bytes of the original length, so the test reaches authenticated decode.
- Carrier/event identity authentication, tenant/canonical-service duplicate lookup and live reader
  cutover remain pending. This change closes only the final incoming database-write guard.

## Review and broader verification

- Calls passes 84 tests. Persistence passes 123 tests with 11 excluded, including the two new
  tagged real-connection cases. Independent review found no production blocker.
- Review strengthened the transaction test: a `FOR UPDATE` probe alone also conflicts with
  weaker locks that would permit account/status edits. Replaced it with actual account rebind
  and credential-status updates, requiring timeout before admission commits and success after.
- Added an explicit already-existing duplicate callback assertion, and qualified historical
  documentation that still described the incoming guard as pending at the prior checkpoint.
- The strengthened six-test group passes. Independent final review found no remaining blocker.
  Format, warnings-as-errors compilation, strict Credo and unused-lock checks pass; all 176
  relative documentation links/anchors pass. Removed incidental formatter changes to unrelated
  functions before staging. The shared umbrella regression follows this focused checkpoint.
