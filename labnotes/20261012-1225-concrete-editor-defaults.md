# Concrete editor defaults

## Scope and decisions
- Remove explicit Default dropdown items in the call spec editor and show the
  actual runtime choice. Preserve omitted source values on read and allow users
  to restore runtime choices without a redundant menu item.
- Runtime evidence: media-policy Effective permits recording/transcripts unless
  a policy denies them, with unrestricted routes when all policies inherit.
  TransferHistory resolves missing/null to fresh; CallSpec defaults tool visibility
  to hidden; WaitSounds assigns phone_ring to call_setup/transfer_to_human and
  cafe_bossa to transfer_to_agent/transfer_joining.
- Participant media Inherit remains a distinct composition rule, not an alias
  for Allow: while-present restrictions combine with call-wide policies.
- Optional models without a configured default use Not configured. Participant
  selectors show inherited models and restore inheritance by selecting the
  call-wide provider/model. No arbitrary provider is chosen when none exists.
- No milestone directory exists in this checkout. No runtime speech transitions
  or source-cutover changed; Lean verification is not applicable.

## Verification
- Red: nine focused test failures for old option names, missing concrete values,
  and inherited provider reset. Implementation then passed these behaviors.
- A preexisting media test assumed selecting Allow always writes true; selecting
  the already displayed default correctly leaves it omitted. Updated the test
  to verify omission and then change Deny -> Allow for an explicit edit.
- Full frontend suite: 586 tests, zero failures. TypeScript and lint passed.
- Rendered headless Chrome review passed for call settings Media, Wait sounds,
  Advanced and participant Transfers at 1440px. Inspected the tool modal and its
  two concrete conversation-mode options at 390px; selecting Blocking works.
- Formatting, warning-free compilation, strict Credo and unused-dependency
  checks passed. Full umbrella: 3,572 tests, zero failures.
- Commit requested for this change and the pending phone-connection checkpoint.
