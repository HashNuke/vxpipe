# Phone connection picker

## Scope and decisions

- User requested compact Web/Phone radio cards, a provider/number modal, server
  inventory search and rejecting published number conflicts while allowing drafts.
- User confirmed owned-account number picking is for incoming Entry. Outgoing
  Entry and human transfers keep destination fields and choose the dialing service.
- User requested WebRTC below Web, provider · number below Phone, and a dash after
  switching to Web. Web switching clears fixed/variable number and phone service.
- Provider protocol lives in Gateway's Twilio/Telnyx inventory adapters, exposed
  through their existing adapter modules. Calls authorizes private service resolution
  and annotates published assignments; Console returns a shared public API contract.
- Twilio lists owned voice numbers; Telnyx lists active numbers attached to the
  scoped application's connection. Both paginate; provider URLs are never followed.
- One transaction locks the tenant's publication scope and rejects another current
  published spec using the same number, across service aliases. Drafts and superseded
  revisions are not reservations; replacing this spec's revision stays supported.
- Added docs/phone-connection-picker.md for the contract and rejected alternatives.
  docs/milestones/index.md is absent in this checkout; no milestone was marked done.

## Red/green evidence

- Persistence duplicate draft/publication test failed before the guard (second spec
  published successfully); focused file then passed. Replacement revisions remain
  allowed and rejected drafts retain an unpublished state.
- Gateway inventory tests failed before the adapter existed; all three passed after
  implementation (Twilio voice filtering/pagination, scoped Telnyx request, fixed
  safe provider failure).
- Two UI card/modal tests failed before implementation; both passed. Additional
  subtitle/clear expectation failed before adding card summaries, then passed.
- Published-number error presentation test failed before the dedicated message;
  implemented a clear conflict message without disabling draft authoring.
- Focused Calls boundary: two tests passed; Persistence publish/directory: 11 passed;
  Console authenticated lookup/inventory endpoint: 11 passed. Endpoint covers
  active assignments, same-spec exclusion, anonymous rejection and secret-safe data.
- Full frontend suite: 581 tests passed; TypeScript and ESLint passed. Formatting,
  warnings-as-errors compilation, strict Credo and unused dependencies passed.
- Full umbrella passed: 3,572 tests, zero failures (seed 496046).

## Barriers and workarounds

- Generic credential service inventory intentionally excludes scoped Telnyx apps.
  Combine its legacy/Twilio choices with the scoped application inventory, preserving
  the existing inventories' separate contracts and marking provider identity.
- Directory ambiguity tests formerly created duplicate publications through the
  publishing API. New guard rejects this; inject historical corrupt rows explicitly
  to preserve the reader's legacy ambiguity detection test.
- Storybook uses explicit fixture inventory via the same loader signature; live
  Console uses its authenticated backend and provider adapters. No real provider
  account data or secrets were accessed.
- Browser semantic locator did not find the native radios immediately after a
  participant selection. Used refreshed snapshots and native radio refs instead.

## Browser and final integration review

- Chrome inspected the main page at 1440x960: Entry cards, provider modal, disabled
  assigned number, selection and provider · number summary, and clearing to Web.
- Phone viewport 390x844: configured picker, disabled-provider/no-service modal,
  Load more and submitted search. No-service Escape does not dismiss the dialog;
  Cancel dismisses it. Explicit search refreshes fixture results and pagination
  adds the next page without losing prior rows.
- New Storybook ChoosePhoneNumber and NoPhoneServices demonstrate these states.
  A browser inspection confirmed source-draft changes on assignment and clearing.
- A focused error display test caught removal of the old registered field boundary.
  Register the connection container with the existing issue context so errors stay
  visible and issue navigation still locates the connection cards.
- Fixed a test fixture missing SourceIssue.code after TypeScript reported it;
  this did not affect production behavior.
- Final frontend suite: 581 tests, zero failures; TypeScript and ESLint passed
  after fixing the test-only issue-code omission. The connection error test is green.
- No runtime speech state-machine or source-cutover transitions changed; Lean lane
  is not required for this authoring/catalog workflow. Commit requested after the modal refinements.

### Modal refinements
- Replaced provider radio cards and the separate service field with one inline
  Telephony service dropdown. Unconfigured providers remain disabled options.
- Updated incoming subheading, removed routine inventory helper text, and added
  distinct empty and fully occupied inventory guidance. A no-match search retains
  its search-specific message.
- In-use rows now show “In use” at the right end without a call spec name. Muted
  text is applied inside the row; divider borders remain outside the disabled
  styling, fixing the asymmetric divider contrast.
- Focused tests failed first for the old labels/status and absent empty-state
  guidance; all five phone tests pass after the change. TypeScript and lint pass.
- Inspected the dropdown and inline status in rendered headless Chrome at desktop
  and 390px mobile widths. The unavailable Twilio option is disabled.
- Rendered the fully occupied inventory on desktop and empty inventory on mobile;
  guidance appears only in its corresponding state and assignment stays disabled.
  Added dedicated Storybook stories for both states.
- Final checkpoint gates rerun after refinements: 3,572 umbrella tests and
  586 frontend tests passed; formatting, warning-free compile, strict Credo,
  TypeScript, lint and unused-dependency checks passed.
