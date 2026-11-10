# Integration catalog source

The canonical integration definitions live in this repository's `integrations/`.
The sixteen initial definitions, schema, template, validator, tests and discovery
evidence moved from the standalone `vxpipe-integrations` repository. Integration
IDs and public data are preserved, with updated JSON Schema locations and one
refreshed Cal.com favicon URL discovered during the real import check.

The sibling `../vxpipe-integrations-web` checkout, relative to this repository's
root, owns the publisher/API. Its GitHub source is `HashNuke/vxpipe`, branch `main`.
It imports only top-level `integrations/*.json`, from one pinned commit. Nested
schemas, templates and evidence are contribution support rather than entries.

## Contribution and publication

Follow [the catalog contribution guide](../../integrations/README.md).
The path-filtered `.github/workflows/integrations.yml` runs the existing Python
schema validation and tests for pull requests and pushes affecting the catalog.
Provider adapters remain application code: adding a JSON definition does not
implement a provider.

The publisher's existing signed GitHub webhook queues catalog refreshes on all
non-deletion pushes to the configured branch. The importer reads the selected
commit's top-level `integrations/*.json`; other application files are not entries.
No new webhook behavior or dispatch system is introduced. Repository, branch,
signature and durable delivery checks remain enforced. Failed imports preserve
the last published catalog; startup can import without a push.

Reuse this existing refresh mechanism. Cross-repository build dispatch, copied
catalogs in the publisher image and a second publishing workflow were rejected
because a data change does not require rebuilding the publisher binary.

## Hosted cutover

The publisher's default, environment example and Railway IaC now select
`DEFINITIONS_REPOSITORY=HashNuke/vxpipe`. Deploy that publisher and update any
existing explicit environment override. Configure a signed JSON push webhook on
`HashNuke/vxpipe` targeting the publisher's `/webhooks/github`, using the same
`GITHUB_WEBHOOK_SECRET`. Retire the old repository's hook after verifying import.
The publisher's own code repository remains `HashNuke/vxpipe-integrations-web`.

The source change does not deploy or alter hosted configuration. GitHub CLI is
unauthenticated in the migration environment, so webhook configuration was not
performed. The old repository is a historical snapshot with a contribution
redirect; keeping it available lets existing deployments finish their explicit
cutover. There is no runtime fallback or synchronization with it.

## Verification

The existing schema validator and five tests moved with the data. Verify the
sixteen definitions retain their payloads apart from `$schema` paths and the
recorded Cal.com favicon refresh. The existing publisher successfully imports
all sixteen definitions and their assets into a fresh local catalog, and its
binary builds successfully. The
[migration labnote](../../labnotes/20261110-0458-consolidate-integration-definitions.md)
records the results. No new automated tests are added for this repository move,
and no hosted cutover is claimed.
