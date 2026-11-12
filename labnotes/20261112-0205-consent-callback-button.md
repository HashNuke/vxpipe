# Consent callback button

## Decision

The user found that manual Codex OAuth login foregrounded a Vxpipe confirmation
URL rather than the callback they needed to paste into the CLI. Their requested
flow keeps confirmation in the same tab and replaces Back to Vxpipe with Back to
my app. Approval and denial now wait for that explicit callback navigation.
Rejected requests retain their recovery link because no callback is trusted.

## Implementation

- Keep the native decision POST and its CSRF/session/one-time completion contract.
  Always render the confirmation; remove the popup-specific presentation field,
  window-target helper and automatic-delivery component rather than retaining
  alternate behavior. The unchanged backend completion supplies the exact
  validated callback, authority snapshot and actual grant expiry.
- Use a native same-tab link for both outcomes, including the JavaScript-free
  rendering. Storybook exercises the same action with a simulated client return.
- Red: six frontend cases fail for the old popup and missing callback action;
  three Console cases fail for the old 302/presentation switch. Green: sixteen
  focused frontend cases and fifteen Console cases. TypeScript, changed-file
  ESLint, root format, warnings-as-errors compile, strict Credo and unused
  dependency checks pass. Production assets and the environment-free Storybook
  build pass. No full suite was run.
- The first red-log read used the wrong working-directory prefix and did not
  start the backend test; corrected the path before running it. No test result
  was inferred from that failed command.

## Browser verification

- Used the existing rollback-only database and local client peers, with synthetic
  users and no production grants or third-party credentials. CIMD and DCR approval
  and denial each show confirmation without creating a new tab or invoking the
  callback. Clicking Back to my app navigates the original OAuth window and
  preserves its client opener. Approval completes S256 exchange, MCP initialize,
  catalog/tool invocation, refresh and session reuse; revocation rejects subsequent
  use with 401 and code replay with 400. Denial preserves state/issuer.
- Desktop approval, mobile denial and the light/mobile Storybook confirmation
  were inspected in Chrome. No overflow; the primary action remains readable and
  the Storybook return action reaches its simulated client state. Approval keeps
  Manage connected clients as the existing secondary link.
- The unreachable loopback callback shows Chrome's connection-refused page after
  the explicit action. Chrome navigation history retains the expected callback
  host/path and full code/state/issuer query, suitable for copying into a CLI.
  The browser tool reports its internal chrome-error URL for this page; corrected
  that inspection assumption by verifying the real navigation-history entry
  through the browser's CDP session. Callback values were not printed.
- Two inspection-script mistakes were corrected: tab records use tabId, and
  agent-browser requires a supported selector instead of Playwright's has-text
  pseudo-class. They did not require product changes. Existing focused HTTP
  cases also verify the no-JavaScript callback link, unchanged CSRF enforcement,
  exact query preservation, failure statuses and rejection of the removed flag.

## Release

Built the production OTP release and Docker image, then restarted Vxpipe.
Both Vxpipe and Caddy services are active, health returns ok, and the published
admin/OAuth JavaScript and CSS match the release artifacts. Running image:
`sha256:f9b0b208cee69f99cce41e599250ec6819ef87b3e55bfbe612d9384ad438e24f`.
The container retains its 1 GiB limit. Temporary browser sessions, test VM,
Storybook server and source copy were cleaned up. No environment files were read.
The user subsequently confirmed successful manual Codex OAuth login through the
new flow; their separately reported MCP protocol-version error is a new follow-up.
