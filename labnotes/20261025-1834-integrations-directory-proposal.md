# Integrations directory proposal

## Scope and decisions

- User requested a researched milestone, smaller tasks and Storybooks for review;
  no production directory fetching, credential persistence or outbound OAuth was
  implemented. Existing dirty changes from earlier work were preserved.
- Default browse/search source is the hosted integrations API. Connected inventory
  remains local. Failure displays installed AI/telephony, and limited outage search
  can retry without losing its query. Tenant custom MCP setup remains available.
- Live API read and external source checked: `category` (not `category_id`), global
  search, case-insensitive version header, opaque pagination, optional version lower
  bound, logo_url. Live catalog currently has three MCPs and no native providers;
  external native definitions/release readiness is an explicit milestone dependency.
- Research covers MCP 2025-11-25 registration priority, discovery, transports,
  security and paginated tools. Client-credentials extension is separate from
  delegated OAuth. Existing inbound OAuth and Console CIMD metadata do not provide
  outbound OAuth callbacks/grants. Console Installation URL retains callback identity.
- Added durable decision doc and one unchecked milestone with T0–T8 vertical tasks,
  ownership, dependencies, tests, migration/runtime cutover and release gates.
  Separate local specification review recorded; user approval remains open.

## Prototype changes

- Healthy AI/telephony browsing consumes simulated returned API pages. Outages
  immediately display existing registered-provider fixtures instead of an empty
  remote category. Connection status, tenant override and global search behavior
  are preserved. New tests distinguish API pages from the local fallback catalog.
- Added registration-required recovery with copyable callback and retained draft;
  failed discovery with edit/retry; missing Installation URL; anonymous automatic
  discovery; and connected-with-zero-tools outcomes. Advanced existing forms remain.
- Corrected discovery outcome to save anonymous authentication in the simulated
  connection; a focused regression first failed, then passed.
- Updated API handoff/schema/examples for actual parameter/optional-version shape.
  JSON examples validate using installed Ajv; all new Markdown local links resolve.

## Verification checkpoints

- `bin/setup` completed dependencies, assets and both local database migrations.
- Initial six new interaction tests failed for the expected absent behavior.
  Implemented the bounded proposal changes, then all 51 tests in the MCP preview
  passed. Anonymous-discovery regression then failed as expected and was fixed;
  preview suite then reached 52 tests passing.
- Full frontend suite: 114 files, 877 tests passing; TypeScript check passed.
- Root formatting, warnings-as-errors compilation, strict Credo and unused-dependency
  check passed. Full umbrella test and Storybook build results recorded below when complete.
- Headless Chrome through agent-browser: desktop 1440×1000 / mobile 390×844;
  dark registration/fallback/manual-client/URL states and light discovery failure.
  Retry restored the global Google results without losing the query. No horizontal
  page overflow at checked widths; disabled OAuth action was observed. Browser
  evidence is under ignored `.impeccable/review/integrations-proposal/`.
- Browser CLI relative screenshot arguments were interpreted as selectors and one
  text wait stalled. Stopped only task-owned CLI calls, used an isolated replacement
  Chrome session and absolute screenshot paths; captures then worked. This was a
  tooling issue, not an application defect.
- Impeccable context/craft floor applied to the existing Console surface. Fonts,
  tokens and layout identity are intentional and preserved; no rule suppressions
  added. Finish review is recorded below after its independent result.

## Design preservation handoff

- Documenter reviewed `PRODUCT.md`, `DESIGN.md`, the targeted directory/recovery
  components and their stylesheet. This is an ordinary Console extension: neutral
  divided rows, inherited admin colors and fonts, existing dialogs and disclosures,
  explicit state labels, and stacked phone controls preserve the Operator's Bench.
- Inspected existing desktop/mobile captures for installed-provider fallback,
  registration, manual client details, Installation URL prerequisite and light-theme
  discovery failure, including the corrected outage empty state. Evidence remains
  in `.impeccable/review/integrations-proposal/`; this handoff ran no new browser or
  test pass. Finish reviewer disposition is ship, with the outage-empty-copy issue
  resolved and no remaining findings reported.
- No new raster assets, reusable visual tokens or typography decisions were needed.
  No token-bearing design-system update is required; `DESIGN.md` and
  `.impeccable/design.json` were left untouched by this handoff.
- Separately flagged existing behavior prose in `DESIGN.md` beginning
  “AI/telephony categories and adapters belong to the installed app”: remote
  directory sourcing now also covers healthy native-provider browse/search; the
  installed catalog supplies outage fallback. The proposal and proposed milestone
  carry that intended contract; this scoped handoff does not repair that prose.

## Final proposal review

- Independent Impeccable finish review requested one material change: zero-result
  outage search must not say Category unavailable. Added a failing regression,
  corrected the empty state, and added a failing-then-passing platform boundary
  regression so platform copy never offers MCP setup.
- Desktop/mobile confirmation captured the corrected empty search. Reviewer verdict:
  ship the Storybook proposal; 1 resolved, 0 partial, 0 unresolved. Scope is the
  proposal and that fix, not certification of future backend behavior.
- Final frontend run: 114 test files / 879 tests passed. TypeScript passed again.
  Final static Storybook build passed; existing large-chunk warnings remain.
  API example JSON validates with Ajv (format checks omitted); local Markdown
  links for the two new documents resolve. New preview suite contains 54 tests.
- The overall milestone and production tasks remain unchecked. No commit created.

- Reconciled the affected sourcing paragraph in DESIGN.md with this proposal after
  the documenter flagged it. This is workflow prose only; design tokens, typography
  and the design sidecar are unchanged.

## Final completion checks

- All five root gates passed, including the complete umbrella run: 4,470 tests,
  zero failures, 156 excluded across ten application suites. No backend changes
  were made for this proposal and no Lean lane was needed.
- Existing Storybook process remains available on port 6006. Task-owned browser
  sessions were closed after inspection; no tmux session or production deployment
  was created.
