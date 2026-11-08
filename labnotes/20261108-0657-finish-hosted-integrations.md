# Finish hosted integrations release

Resumed from `4f945361` with a clean worktree. The prior turn completed the
hosted acceptance automation and default verification; its unresolved release
access was a real external blocker. Fresh inspection now finds authenticated
Railway MCP and CLI access to the existing integrations project. No new project,
service, storage or credentials are needed.

Both sibling repositories are clean and their remote `main` branches already
contain the reviewed release: definitions `40d763a`, publisher `a5ed7a5`.
The live service still runs its October deployment and serves only three MCPs.
The exact Console live test fails for missing native adapters (seed 806608).
This is release evidence, not a newly discovered implementation defect.

`bin/setup` succeeds for this checkout. Fresh definitions validation covers all
16 entries and the template; five schema tests pass. Publisher `go test -race
./...`, `go vet ./...` and server build pass with Go 1.26.0. The publisher release
does not change database migrations, hosting limits or secret configuration.
An immediate backup through the existing service's supported backup command
succeeds before deployment. It creates a private SQLite snapshot and checksum;
the object path is kept in the operator session rather than source.

Requested independent GPT-6 Astra xhigh review, including the adversarial
directory boundary and release hazards. Early source review confirms local
native-adapter allowlisting and anonymous closed directory requests. Release
verification must check the complete catalog and actual logos, not just health
or readiness of the retained old catalog. The documented stable-logo-key
atomicity limitation and incompatible-old-publisher rollback restriction remain.

The user requested sibling repository guidance in AGENTS and subsequently
required commits and pushes for every changed repository. Added relative paths
in `1fb0713b` and pushed it to `origin/main`; no supporting repository source
has changed during this continuation.

The publisher deployment reaches SUCCESS, retaining the existing volume, single
replica, limits and configuration. Its worker safely retains the old catalog while
retrying a failed import. A fresh isolated import independently reproduces the
cause: Cal.com's deployment-qualified favicon is no longer advertised. All 16
official landing pages were checked again: Cal.com is the only stale declaration;
14 other supplied icons remain declared and MorseCode still has no declared icon.
Astra independently reproduces the old URL's absence and verifies the current
highest-ranked 512×512 PNG by its response type and PNG dimensions.

Changed only Cal.com's `icon_url` and added dated discovery provenance in the
definitions repository. The five schema tests and all definitions pass again;
the actual complete-catalog import now succeeds. The strict publisher policy is
unchanged. Production will use its owned durable retry worker after the corrected
definition is pushed, never a concurrent standalone sync on the live database.
