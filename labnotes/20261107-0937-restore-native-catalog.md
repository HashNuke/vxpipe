# Restore the native directory release

The user confirmed `vxpipe/vxpipe-integrations` as the definitions repository and
the existing sibling checkout as its location. Its clean remote main contains
only the three calendar MCP definitions. The clean publisher checkout is at
`43a8975`; neither remote contains the earlier unpushed native release checkpoints
recorded in [the original evidence](20261107-0859-native-directory-release.md).

Recreate those changes from the recorded approved contract, with fresh red/green
evidence. Native definitions may omit an icon; MCP icons remain mandatory and an
explicit invalid/empty/null icon remains an error. Preserve supplied-icon failure
atomicity and retained snapshot metadata. Then revalidate the 13 release adapter
IDs, official source/icon provenance and actual local import/API output. No public
push, deployment or hosted sync has been performed during this recovery.

The current host lacks Go and has an older system jsonschema. Preparing the
publisher's declared Go 1.26.0 toolchain through mise and the definitions' pinned
Python requirements in an isolated temporary virtualenv before obtaining red tests.

Go 1.26.0 installed successfully. System Python lacked ensurepip; `uv venv` and
`uv pip` prepared the pinned jsonschema environment without modifying system
packages. The reconstructed schema regression failed for required `icon_url`, and
three publisher regressions failed at parser, syncer and API projection as expected.

Before implementation, the user pushed the original definitions changes from the
other machine and requested a pull. Preserved the new, redundant local schema test
outside the repository, then fast-forwarded cleanly to `9eef75c`. This recovers
`b09222a`, `0d5fff6` and `9eef75c`, including all 13 native entries and their original
source/icon reports. The recovered five schema tests pass; all 16 definitions and
the template validate. No recreation of the definitions is now needed.

A fresh publisher fetch still has no newer remote commit than `43a8975`. Asked
the user to push that repository's matching changes too, or choose reconstruction.
The three new publisher regression files remain uncommitted; no implementation,
public push, deployment or hosted sync has been performed.

The user also pushed the publisher. Preserved the three reconstructed regression
files outside that repository, then fast-forwarded cleanly to `a5ed7a5`, recovering
both optional setup metadata and native icon support. The full Go race suite, vet
and server build pass. Both repositories are now clean; the original implementations
are recovered and no replacement implementation is needed.

A fresh complete-catalog import into an isolated local SQLite database fails on
Deepgram: its configured icon URL is no longer declared by the current landing
page. Added the source-refresh task to T1 and requested independent reproduction.
Inspect all recovered icon candidates before changing definitions or attempting
publication. The earlier local-import evidence remains historical, not current
release proof.

Independent Astra discovery reproduced stale deployment-dependent URLs for both
Deepgram and Google AI. The parent checked all 16 landing pages with the existing
read-only icon CLI: these are the only mismatches; all other supplied icons remain
advertised and MorseCode still declares none. Updated those two definitions and
their existing provenance report with the current highest-ranked usable candidates.
The five schema tests and all 16 definitions pass again, and actual complete-catalog
import now succeeds without changing publisher policy.

The resulting real local API serves 16 entries, exactly the 13 release-native IDs,
11 AI and two telephony entries. Platform scope serves 13 native entries; global
Google search serves both native and MCP entries. MorseCode omits logo_url and
the other native entries have assets. The first Console validation used a local
HTTP asset origin and correctly rejected that fixture as invalid; the API was
restarted with an HTTPS asset base before repeating schema validation. Public
read-only revalidation still returns three MCP entries and zero native entries.

Installed Railway CLI 5.71.0 after npm required explicit permission for the package's
postinstall binary download. Its one-time tooling health check reports current
skills and configured MCP; the CLI itself is unauthenticated. No hosted operation
has been attempted. All questions and their options must also be sent through
pushnotify, per the user's clarification during this checkpoint.

Console's actual Page.validate boundary accepts all four corrected-fixture API
responses (tenant, platform, categories and global Google search). Astra reviewed
the exact three-file correction and full catalog evidence without a new reproduced
defect. Committed the definitions correction as `40d763a`; it has not been pushed.
The compatible publisher must be deployed before publishing the final definitions
and running a successful public sync. Asked through chat and pushnotify whether
to start CLI sign-in, use a connected Railway plugin, or have the user deploy the
publisher. No hosted state has been mutated. HTTPS asset URLs in the local JSON
establish schema compatibility, not actual asset delivery.
