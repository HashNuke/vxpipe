# Connected clients and consent review

## Requested changes

- Expose the missing Connected clients destination in Storybook and connect it
  to the consent journey. Repository inspection found the real revocation section
  already wired in production `/account`, but omitted from both Storybook account
  navigation harnesses.
- Remove Storybook/protocol explanations from the product screens. Replace the
  outcomes with proposed app copy, branding, explicit state and useful navigation.
- User selected **Back to Vxpipe** as primary action on approval and
  **Manage connected clients** as a secondary text link.
- Make the client website clearly clickable with a globe, permanent underline
  and the existing link color.
- User authorized committing and pushing the completed work. Current branch is
  `qa`, initially even with `origin/qa`; existing uncommitted OAuth preview work
  belongs to this same conversation and is included in this checkpoint.

## Implementation

- Reuse the actual ConnectedClients component with a local API adapter. Add a
  standalone page preview and populated, empty, loading, load failure, revoking,
  failed-revoke and success stories. Both account harnesses preserve fixture
  revocations across account navigation.
- Production ConnectedClients gains an announced success message and clearer
  list presentation. Backend OAuth and route behavior remains unchanged.
- Consent links to connected clients. Approval returns to Console home and offers
  revocation as a secondary link. Decline and unavailable states also have a
  working Console return. No prototype explanations or callback parameters are
  rendered on the completion screens.
- Documentation distinguishes proposed completion/standalone account pages from
  the current production redirect and embedded revocation section.

## Verification

- Red: five focused failures covered missing revocation status, destination,
  consent link and product outcome copy. Green: all ten focused checks passed.
- CTA feedback had a separate red run: two failures for secondary-link semantics
  and Console-home navigation. Updated relevant suite: 98 tests pass; TypeScript
  and changed-file ESLint pass.
- Final focused interaction set: 11 tests pass after CTA and heading updates;
  TypeScript, changed-file ESLint and Storybook production build pass.
- Headless Chrome verified consent links, approval/decline, desktop/mobile
  layouts, connected-client navigation, successful revocation, empty state and
  failed revocation. A transient blank capture during Storybook reload was
  replaced after the actual page content returned. Mobile heading alignment
  was corrected and the affected states recaptured. No browser exceptions.
- Fresh independent finish review after user feedback returned `ship` with no
  material fixes. It explicitly checked product-only copy, the primary/secondary
  CTA hierarchy and globe/underline website affordance.
- The full umbrella run completed with one failure in the unchanged MCP lifecycle test
  `local revocation retires an integration before its client is registered`
  (one failure in the initial run). The complete `ConnectionsTest` file passed
  (11 tests), then the whole MCP application passed (222 tests, 71 excluded).
  A final root `mix test --failed` reran that one recorded test and passed;
  every other application reported no failed tests to rerun. This is recorded
  as an intermittent initial-suite failure, not an initially green umbrella run.
  No backend code changed.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed. Documentation review also passed with existing design context
  preserved. Storybook remains available on port 6006.
