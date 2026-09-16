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
