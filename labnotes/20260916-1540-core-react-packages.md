# Core and React packages

## Core call-details checkpoint

- Confirmed both workspaces already author source in TypeScript. The existing Core package exposed
  only a combined prototype `CallSnapshot`/`VxpipeClient`; React consumed that contract directly.
- Added a failing focused Core suite using typed mock call-details endpoint responses. The initial
  failure was the expected missing `createCallDetailsStore` export.
- Implemented the framework-neutral call-details types, normalized store, and injected loader
  controller. The store reconciles revisioned entities, explicit tombstones, deterministic timeline
  order, page overlap, variables, call incarnation, and raw RTVI receipt immutability.
- Split presentation types into `types.ts` so the call-details implementation does not import back
  through the package barrel.
- Added package test/build scripts and documented host-owned fetching. Core owns normalization and
  reconciliation; it contains no endpoint, authentication, React, or Phoenix dependency.
- The first workspace-local test script used a package-relative filter while the shared Vitest
  configuration matches root-relative paths, so it found no tests. Changed the script to set the
  workspace root explicitly and retained the shared configuration.
- Evidence: five focused Vitest tests pass, the Core TypeScript declaration/ESM build passes, and
  the root strict TypeScript check passes.

## React controller checkpoint

- Added failing React tests using typed mock endpoint responses for an ended call and an ongoing
  call inspected without joining RTVI. Both initially failed because `CallConsole` still required
  the old combined client.
- Replaced the combined client prop with a host-composed `CallConsoleController`: durable details
  are required, while history actions and live controls are optional. Remote calls render without
  device controls, a call action, or a composer; attaching live controls restores those actions.
- Moved the combined rendering shape inside React as a derived view model. Core now exposes only
  durable call-details, loader/controller, and local live-control contracts.
- Migrated Storybook to a TypeScript fixture controller that projects its synthetic state into the
  same call-details and local-session shapes. Existing interaction stories and tests use the new
  boundary.
- Added explicit remote-ended and remote-ongoing stories. Rendered desktop and 390px browser checks
  showed remote data without device/call/composer controls and preserved the attached-live layout.
- Package dry runs exposed stale files left in `dist` by incremental source deletion. Added an
  explicit clean step before each package build so tarballs contain only current ESM, declarations,
  CSS, manifests, and README files.
