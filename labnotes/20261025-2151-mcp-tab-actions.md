# MCP tab actions

## Requests and scope

- Put Reconnect beside its explanation in the Authentication tab. Keep the modal
  footer consistent between Authentication and Tools.
- Replace the Tools refreshed message with an icon that spins while Refresh tools
  is disabled, then returns to its normal state on completion.
- Storybook implementation only; authentication and refresh remain simulated.

## Implementation

- Reconnect and Save changes now belong to the authentication form. Disconnect and
  Close stay in the modal footer regardless of selected tab or credential edits.
- Reconnect has type=button inside the form so it cannot accidentally submit it.
- Refresh has disabled and aria-busy states during an 800ms simulated request.
  The spinner respects reduced motion. The effect clears its timer on unmount.
  No success text is inserted, so content and footer positions remain stable.

## Evidence

- Expanded focused tests before implementation: four failed and one passed. Failures
  showed Reconnect outside Authentication, a changing footer, and an enabled refresh
  button after clicking. After implementation, all 29 focused MCP tests pass.
- The tests cover both Cal.com and registered OAuth credentials (HubSpot), retain
  draft edits across tabs, and verify refresh returns to an enabled state without
  adding success text. TypeScript passes.
- Browser inspection and remaining completion checks follow.

## Rendered and frontend verification

- All 901 frontend tests in 118 files pass; TypeScript and static Storybook build
  pass. Existing chunk-size and jsdom scrollTo notices are unchanged.
- Headless Chrome at 1440px and 390px: Reconnect stays beside its explanation;
  both tabs keep Disconnect/Close in the same footer. HubSpot Save changes is inside
  Authentication and reachable by scrolling the tab body on mobile. No page overflow.
- Browser computed state while refreshing: disabled=true, aria-busy=true,
  animation-name=spin. On completion: disabled=false, no busy attribute,
  animation-name=none, and no Tools refreshed text. Mobile keeps the icon-only
  control; the list and footer do not move.
- This is a refinement of the existing modal. No fonts, palettes, permissions,
  real network behavior or backend contracts were expanded.
- Umbrella completion gates pass: format, warnings-as-errors compile, strict
  Credo, unused-dependency check, and 4,470 tests with no failures (156 excluded).
