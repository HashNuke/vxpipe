# Implement MorseCode API

## Start

- User authorized implementation, small commits and final Vxpipe push on branch
  `morsecode-api`; Go repository is `HashNuke/morsecode-audio`.
- Committed the reviewed plan as `93d3d1b8`. Cloned the empty Go repository.
- `bin/setup` completed successfully. Existing developer environment preserved.
- `pushnotify` startup notification succeeded. Use it for checkpoint updates.
- Go 1.26.1 is installed through mise but absent from the current PATH; use the
  pinned toolchain explicitly until repository tool selection is configured.
- Downloaded the public ElevenLabs OpenAPI schema for a content-hashed speech
  contract snapshot. No live speech requests or private provider file access.
- Asked the user to resolve the milestone's no-retention exceptions; independent
  synchronous/streaming work continues while that question is pending.

## Checkpoint A

- Initial red: API/config package tests failed because implementation packages
  did not exist. Green: focused tests, `go vet ./...`, `go test -race ./...`.
- Captured 13 HTTP paths and 53 transitive schemas, preserving fields/defaults
  and recording full/reduced source SHA-256 digests. Python SDK pinned to 2.72.0.
- Official SDK local discovery passed; six JSON response schemas validated,
  missing credentials rejected. Binary served a nondefault local port and exited
  cleanly after SIGTERM. Two different synthetic keys accepted.
- Complete WS contract snapshot and no-retention decisions remain open; A is
  partially complete, not an accepted full compatibility checkpoint.
- Go checkpoint committed as `468c387` (authenticated discovery service).
