# Review integration checkpoints

## Scope and commit decisions

- Reviewed accumulated Console, version-source, documentation, public integration
  definition, and private directory API changes before committing. The user asked
  for coherent checkpoints and removal of the 2px service favicon padding.
- Separated bundled favicons, shared VERSION wiring, breadcrumb primitives, hosted
  API contract, implementation proposal, preview data, and the integrated
  Storybook workflow. The favicon inventory assertion correction is a separate
  commit because the earlier checkpoint had already been committed.
- Kept the new workflow and existing story adapters together: the adapters depend
  on the new modal and directory components, and shared provider-card changes must
  land with their updated consumer assertions.
- The external API's optional setup metadata and the public definitions are
  separate commits. The API accepts the old singular setup-note field while
  returning the plural field. Deploy that reader before publishing new definitions.
  Existing JSON storage needs no SQL migration for these optional fields.
- No push or deployment was performed. No production directory client or outbound
  MCP authentication flow was added; the milestone remains incomplete.

## Findings and fixes

- Removed `.service-logo-image` padding. Bundled favicon assets load on desktop
  and mobile; unknown services retain the neutral placeholder.
- Found AI/telephony pagination cursors being discarded when restoring preview
  routes. Added a failing interaction test, retained the cursor for every browse
  category, and verified Back/Forward, remount, and rendered-browser reload.
- Found custom MCP authentication choices reverting to bearer defaults on Manage.
  Added failing Basic and OAuth client-credentials cases, retained the non-secret
  mode/grant/client-auth selections, and verified secrets remain blank.
- Corrected stale directory handoff descriptions of inherited labels and outage
  behavior. Reviewed permission gating, platform/tenant separation, metadata
  optionality, preview-only boundaries, and the required future backend contracts.
- Retained the existing Console visual language; no unrelated typography changes
  or new suppressions were introduced.

## Verification

- All umbrella gates passed: format, compile with warnings as errors, strict
  Credo, tests, and unused-dependency check. ExUnit reported 4,470 tests across the
  ten applications with zero failures; explicitly excluded live lanes stayed out.
- All 915 frontend tests across 119 files passed, TypeScript passed, and Storybook
  built successfully. Focused review regressions failed before their fixes and
  passed afterward. No source-cutover or speech state-machine changes require Lean.
- Headless Chrome inspection covered the directory and favicon padding at desktop
  and mobile sizes, pagination/reload, and reopening Basic authentication. Earlier
  UI checkpoint notes record the broader modal, theme, permission, loading, and
  responsive inspection. Storybook remains available on port 6006.
- The private directory API passed Go tests with the race detector, vet, and build.
  Public definition validation and all four schema tests passed. JSON response
  examples validate against their schema and changed documentation links resolve.
- Reviewed staged diffs and checked for whitespace problems, generated files,
  secrets, and local absolute paths before committing.
