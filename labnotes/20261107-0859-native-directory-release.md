# Native directory release readiness

T1 external prerequisite research and implementation, alongside the frozen local
in-flight acceptance gate. The separate `vxpipe-integrations` definitions repository
and `vxpipe-integrations-web` publisher/API repository both started clean.

## Initial state and approved contract

- The 0.1.0 release manifest already contained the 13 public native adapter IDs.
  The definitions repository initially contained only the three calendar MCP entries.
- The main Registry also contains `morse`, a credential-free local proof provider
  explicitly restricted to test configurations. The public `morse_code_api` adapter
  has credential and validation capabilities and is present in the release manifest.
- The definitions schema and Go parser initially required `icon_url` for every integration;
  the syncer always fetched/uploaded an icon; the read API built a logo URL even
  when ObjectKey is empty. Console already has neutral native fallback rendering.
- Implement omission of `icon_url` for native providers only. MCP icon requirements
  remain unchanged. Explicit empty/null/insecure supplied icons remain invalid;
  a failed fetch of a supplied icon must still abort the catalog import.
- Missing native icons publish no asset/provenance metadata and omit `logo_url`.
  Never invent branding or return a bucket-root URL as a logo. Existing SQLite
  string columns permit empty metadata; preserve immutable prior snapshots.

## Red-first evidence

New Go regressions fail independently at parser, publisher and HTTP projection:
native omission is rejected; sync still calls the icon fetcher; the API emits the
bucket root as `logo_url`. A matching Python schema regression was added, but its
first run could not import the pinned jsonschema dependency. Preparing an isolated
temporary virtualenv from requirements-dev.txt before obtaining the real red test.

The web reader could not fetch the MorseCode homepage. The repository's read-only
icon discovery CLI fetched it and returned an empty `candidates_best_first` list.
At that stage no catalog definitions, public deployment, push or live sync had
been performed.

The isolated Python schema run then failed for the expected required-icon rule.
After implementing native-only omission, all five schema tests and all three
existing definitions validate. Go parser/syncer/API regressions pass, and the full
Go race suite passes. The native no-icon sync regression replaces a prior icon
pointer with empty metadata and confirms there is no bucket upload; a later supplied
icon failure preserves the prior published revision. Console's shipped schema
already leaves logo_url optional and uses its installed native logo/neutral fallback.
Full Go race, vet and server build checks pass. Independent review required evidence
that earlier snapshots keep their complete asset/provenance metadata, now asserted
by reading the retained old revision after icon removal. It also required explicit
upgrade/rollback order: upgrade publisher/API before iconless definitions; rollback
requires a compatible pre-change database snapshot or expiry/pruning of every
incompatible historical snapshot. Republishing a compatible current catalog alone
does not remove revision/cursor access to retained incompatible history.

Native source discovery fetched the official landing pages for all 13 adapters.
The OpenAI marketing and platform pages return HTTP 403 to the publisher; its
official developer landing page is accessible and declares a 48-pixel PNG icon.
The other fetched pages provide declared candidates, except MorseCode API as above.
The optional-icon prerequisite passed exact staged adversarial review and is
committed locally: `vxpipe-integrations` at `0d5fff6`, publisher/API at `a5ed7a5`.
Neither repository was pushed or deployed.

All 13 native definitions are now prepared with official documentation links,
declared icon candidates and a checked provenance report. Their provider IDs exactly
match the release manifest, without duplicates. Five Python tests pass and all 16
definitions validate. The first real local-only sync was blocked by an existing
Cal.com definition whose icon is no longer advertised by its landing page. Inspected
all three MCPs' current declared candidates and updated only the stale Cal.com URL
to its declared 512-pixel PNG. A separate provenance report records the candidates.
The publisher's declared-icon rule and MCP icon requirement remain unchanged.

## Local complete-catalog acceptance

- Real local-only sync now succeeds for all 16 definitions, including actual
  favicon downloads/inspection and local asset publication. This uses an isolated
  temporary SQLite database and filesystem buckets, not the public directory.
- The built HTTP server returns 16 entries, exactly the 13 release-native IDs,
  11 AI entries and two telephony entries. Platform scope returns only the 13
  native entries; global Google search includes native and MCP entries. MorseCode
  has no logo_url; all other native entries have uploaded asset pointers.
- Console's production Page.validate boundary accepts the actual 16-entry local
  response using the installation's compiled 0.1.0 version and installed adapters.
- The local server is stopped after acceptance. The exact 16-file definitions
  checkpoint passed independent adversarial review and is committed locally as
  `9eef75c`. Both external worktrees are clean. No public push, deployment or sync
  was performed.
- A fresh read-only request to the public API with `X-VxPipe-Version: 0.1.0`
  returns HTTP 200 and three MCP entries, with no next cursor and no native entries.
  Public deployment/sync and live native release verification therefore remain
  pending; the complete 16-entry evidence above is explicitly local.
