# Simplify MCP connection forms

## User decisions and implementation

- User requested no editable connection names, directory-owned endpoints/auth, and
  no callback fields for CIMD/DCR. Kept changes inside Storybook previews and docs.
- Separated directory credential rendering from custom-server configuration. Listed
  OAuth services show a compact authorization prompt; registered-client services
  show required credentials plus callback only for manual provider registration.
- Custom servers retain URL/auth settings and use the initialized server name
  (Office tools fixture). Validation no longer requires an invisible name input.
  Connected fixtures now use Cal.com and HubSpot, without redundant service labels.
- User then moved the directory outage notice beneath category navigation, with
  exact supporting copy: Showing built-in AI and telephony services. Added one
  shared navigation/status region, mobile selector placement and compact retry icon.
- Updated milestone and proposal contracts, including metadata-derived naming and
  durable identity independent of display-name collisions. Backend remains unbuilt.

## Verification

- bin/setup completed. Eight focused form tests failed first, then passed. All
  existing preview tests were updated for the new name/configuration contract.
- Sidebar location/copy tests failed before implementation; final focused run: 63
  tests passing across nine files. Full Console run before the sidebar steering:
  887 tests passing. Final full run/build recorded below after verification.
- TypeScript and root format/compile/Credo/unused-dependency gates passed. Complete
  umbrella suite started and is still being collected. No backend source changed.
- Browser captures through headless Chrome: desktop1440x1000/mobile390x844, compact
  Calendly, registered Google Calendar, custom MCP in light theme and outage sidebar.
  Saved under ignored .impeccable/review/mcp-fields. No new fonts or design tokens.
- Existing unrelated dirty work preserved; no commits created.

## Independent design-documentation review

- Read PRODUCT.md, DESIGN.md, the scoped authentication/directory components and
  stylesheet, and the updated workflow prose. The documented field visibility and
  outage placement/copy match the source; the incumbent Console typography,
  semantic colors, flat borders, dialog controls and responsive patterns remain.
  DESIGN.md's token frontmatter is unchanged. No design-document update is needed.
- This was a source/documentation review only; it did not rerun browser checks,
  frontend tests or backend verification, or establish live OAuth behavior.

## Final UI checks

- Final Console suite: 115 files, 888 tests passed. TypeScript check and static
  Storybook build passed after the sidebar change; only existing bundle-size
  warnings remain. Shared frontend workspace suite also passed all 40 tests.
- Manual browser retry restored the directory from the new sidebar icon. Mobile
  custom DCR has only URL/auth labels, no callback/name input, and page scroll width
  matches the 390px viewport. Dark/light and desktop/mobile captures were inspected.
- Independent Impeccable finish reviewer returned ship with no material findings
  after reviewing all ten named captures and scoped source. No design-rule ignores
  or token changes were added. Final docs preserve the Storybook-only boundary.

- Complete umbrella run finished: 4,470 tests, zero failures, 156 excluded across
  ten application suites. All five required root gates passed. Task-owned browser
  closed; existing Storybook server remains on port 6006 and responds HTTP 200.
