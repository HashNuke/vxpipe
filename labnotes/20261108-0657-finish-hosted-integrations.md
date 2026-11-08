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

## Hosted acceptance

The reviewed correction is committed and pushed as definitions `4b8d15d`.
Publisher `a5ed7a5` runs in successful Railway deployment
`2dde5389-e81c-4047-ac5d-0892c9137eb0`. Its durable worker reports completion after
the GitHub push; no manual publication or queue rewrite was needed. Public GitHub
resolves `main` to the corrected definition commit. An additional diagnostic
import on the deployed container also succeeds using an isolated ephemeral
SQLite database and local object storage, never the production database or bucket.

The hosted catalog now contains 16 entries at revision
`7d5e4d161e0c03e1423f691e15adc9c67ea30cf9ad37b8d0a15ebe5cc71cba7c`.
From the Console child, the documented command
`mix test test/integration/integrations_directory_live_test.exs --include live_integrations_directory`
passes: one test, zero failures, seed 951735. It verifies the complete installed
native adapter set, tenant MCPs/categories, native category filters, platform MCP
exclusion, global mixed-case search and the actual versioned client contract.
Both hosted health and readiness endpoints return HTTP 200.

All 15 supplied logo URLs return HTTP 200 with image content types and nonempty
bodies through curl. MorseCode alone correctly omits `logo_url`. Python urllib's
default client was rejected by the storage edge with HTTP 403/code 1010, so that
failed probe is not counted as asset acceptance. Chrome through `agent-browser`
successfully loads all 15 images with positive natural dimensions and a
`no-referrer` image policy. The rendered 1280×900 logo grid was inspected; it is
an isolated asset harness, not a claim of rerunning authenticated Console flows.
Chrome initially lacked a usable host sandbox and was relaunched with the local
acceptance runner's explicit `--no-sandbox` option. No storage policy was changed.

Astra's focused xhigh review finds no new reproduced code defect. The only new
release correction is Cal.com's independently reproduced metadata drift, whose
exact two-file change was reviewed before commit/push. The existing caveats about
stable icon keys and old-binary rollback remain recorded in publisher docs.

This continuation changes documentation and one external definition, not Vxpipe
runtime code or dependencies. The prior five root gates (5,000 tests, zero failures,
265 exclusions, seed 774698) and frontend verification therefore retain their
recorded scope. Current proportionate checks cover definitions, publisher build/
tests, real import, deployed client behavior and hosted assets. Lean does not apply.

Reconciled the milestone, index and current documentation with hosted completion.
The explicit workflow approval required by T0/T8 is still pending; the approval
question and choices were sent in chat and pushnotify. Neither the index checkbox
nor the final completion notification is marked complete before that answer.

Final Astra xhigh reconciliation review independently inspects the saved hosted
response, passing live-client output, rendered logo screenshot and ten-file
documentation diff. No change is requested. The exact 13 native IDs and all 16
entries match; evidence claims distinguish the asset harness from earlier
authenticated acceptance. All 331 local Markdown link targets in the changed
documents resolve and `git diff --check` passes. Railway reports the service
Online, zero issues/recent failures and no pending staged or applying work.
