# Participant audio and transcript routing

## Scope

- Remove audio routing and transcript routing from Call settings Media.
- Keep both controls in agent and human participant Media tabs, editing their
  while_present policies. Preserve existing call-wide routes when editing other
  settings; this is an authoring UI change, not a schema migration.
- Red: two focused failures showed the routing controls still present in Call
  settings. Move existing route-edit coverage to participant policies and cover
  both human and agent routing without changing call-wide policies.
- No speech state-machine or source-cutover changes; Lean is not required.

## Verification

- Focused settings, agent and human suites: 44 tests passed. TypeScript and lint
  passed. Browser review confirmed Call settings shows only Record audio and Save
  transcripts; agent Media retains both routing controls. Human Media with saved
  restricted transcript routes rendered correctly at 390px.
- Root completion gates passed: formatting, warning-free compilation, strict
  Credo, 3,572 umbrella tests with zero failures, and unused dependencies.
