# Wire OAuth forms

- Next scope: production CIMD, DCR and registered-client forms, advertised grant/
  client authentication, Console callback identity and nonsecret callback recovery.
  Static inventory/UI remains a separately reviewed checkpoint.
- Found a multiline-secret input issue: hidden private keys use a password input,
  which cannot represent newline-preserving entry. Do not backfill multiline values
  through a single-line editor. A focused red test and UI decision are pending.
- Research: MDN documents -webkit-text-security for textarea obfuscation but marks
  it nonstandard. Avoid relying on unsupported CSS to keep a key visually hidden.
  Consider explicit reveal-to-edit for multiline secrets while preserving the
  original textarea value across hide/show. No implementation decision applied yet.
  Source: https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/-webkit-text-security

- Multiline secret red tests reproduced editable single-line input and dropped
  textarea constraints. Hidden multiline values now require explicit reveal to
  edit; hide/show preserves the complete value. Revealed fields retain disabled,
  required and length constraints. Eight focused files / 57 tests pass.
- Discovery parsing red tests reproduced missing supported grants/callback identity
  and accepted invalid identity data. Return the backend grant list and exact
  HTTPS Console callback/client-metadata identity; never invent a callback. Eight
  parser/hook tests pass, plus TypeScript.
- Added OAuth form model and field regressions before the modules existed. Seven
  tests now cover challenge-first scopes, advertised grants/authentication/signing,
  managed-field exclusion, public/secret/JWT isolation and machine/browser field
  separation. Managed CIMD has no editable fields; DCR has only initial token.
- Added four production-dialog red cases for CIMD/DCR handoff, machine connection
  through the existing endpoint and malicious redirect rejection. Wiring is in
  progress; saved OAuth management, return/draft recovery and rendered verification
  are still pending. No browser authorization was performed against a real provider.
- Saved OAuth management now parses the real registration/grant/auth labels,
  retests using catalog-only refresh and requires explicit credential replacement.
  Partial discovery no longer implies OAuth readiness. Eleven focused tests passed.
- Callback recovery tests were written first (seven initial failures), then wired
  through the production wrapper and authenticated actor. Store only a bounded
  nonsecret whitelist, bind it to actor/tenant/attempt, consume once, reenter secrets
  and require current inventory before connected feedback. No new native APIs.
- Adversarial review found unsupported saved browser-OAuth endpoint replacement,
  lost callback recovery after an expired directory cursor, and an overstrict
  encoded return-path length. Added red regressions before each fix. Endpoint
  changes now explain new-connection creation; cursor recovery retains original
  attempt context; valid percent-encoded paths use the server's path bound within
  the existing 8 KiB storage limit. Also reject malformed timestamps/control text.
- Chrome fixture inspection: CIMD desktop and DCR mobile show only their required
  fields; DCR Connect simulates handoff without network/provider navigation.
  Own-client private-key hide/show preserves all four synthetic lines. Remaining
  checks and final independent checkpoint review are in progress.

- Rendered return fixtures cover denied consent, expired-cursor restart and retry,
  plus connected feedback from fixture inventory. Inspection found the recovery
  explanation behind the modal; a red within-dialog assertion now protects its
  placement inside the restored form. Eleven focused return/field tests pass.
- A full 1,008-test frontend pass preceded two additional draft-boundary tests.
  A subsequent 1,010-test run overlapped the umbrella suite and hit two unrelated
  5-second frontend timeouts (tenant access and participant JSON). That umbrella
  run also hit bounded Gateway media failures. Do not infer causality from timing;
  inspect and rerun without competing suites before closing the verification gate.
- A late-identity regression reproduced lost cursor recovery when directory data
  arrived before the session actor. Capture only the original tenant/attempt
  navigation context early; defer draft consumption, restoration and feedback
  until authenticated actor and authorized inventory are ready. Ten return tests
  pass after the fix. Actor/tenant matching remains mandatory.

- Final checkpoint verification: all 1,011 frontend tests across 134 files pass;
  TypeScript passes; ESLint has no errors (one existing SetupDialog dependency
  warning). Root format, warnings-as-errors compilation, strict Credo and unused
  dependencies pass. The isolated full umbrella rerun passes 4,887 tests with zero
  failures and 201 exclusions (seed 825059). The 23 affected Gateway media tests
  also pass separately with the earlier seed 541142. No media runtime/test change
  was made here; these reruns do not claim to repair the intermittent load failures.
- Independent adversarial exact-index review found no remaining issues after
  endpoint, cursor, encoded-path and late-identity fixes. All fixes are milestone
  tasks. Chrome desktop/mobile fixtures cover CIMD/DCR, own-client multiline keys,
  machine connection, denied/cursor-recovered retry and current-inventory success.
  The browser session is closed. Actual authenticated provider/browser acceptance
  remains open; this checkpoint does not finish the milestone.
