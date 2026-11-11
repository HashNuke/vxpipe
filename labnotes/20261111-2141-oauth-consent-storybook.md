# OAuth consent Storybook

## Scope and direction

- Add a reviewable design proposal for inbound platform MCP authorization. Keep
  production authorization behavior unchanged; the requested artifact is Storybook.
- Extend the established Operator's Bench in Operate mode: quiet centered layout,
  client identity, plain-language authority, explicit scope, and inspectable details.
- User requested optional CIMD logo metadata with an icon fallback and a pushnotify
  message once the work is ready for review.
- Initial worktree was clean. Ran `bin/setup` successfully; assigned Storybook 6006.

## Findings and decisions

- Current `ConsentPage` renders raw permission keys and URLs. Both decisions in
  `AuthorizationController` immediately return HTTP 302; the client owns the next
  screen. Review outcomes explain that handoff instead of inventing client UI.
- RFC 7591 defines client_name, client_uri and logo_uri; MCP 2025-11-25's CIMD
  example uses them. The current profile drops CIMD logos and rejects DCR logos;
  consent does not expose the already-retained client_uri. Documented that gap
  for production adoption without broadening this preview into a backend change.
- Codex branding uses the user's public metadata example. Account/authority data
  and callback code/state are synthetic. HTTPS images use no-referrer and an
  on-error Lucide Plug fallback. No trust/verification badge is implied.
- Dedicated Allow/Deny stories exercise local state transitions. Other stories
  cover absent/broken logos, DCR, all tenants, no permissions, request failure,
  long names and light theme. Buttons can replay either decision.

## Verification

- Red: focused tests failed on the missing OAuthConsentStory module before implementation.
- Green: 4 focused interaction/branding/authority tests; 87 relevant authentication
  and Console story tests pass. TypeScript and changed-file ESLint pass.
- `npm run build-storybook` passes. Development server is running at port 6006.
- Headless Chrome via agent-browser: inspected desktop 1440px, mobile 390px,
  long-name stress 320px, light theme, failed logo, expanded metadata, Allow and
  Deny handoffs. Source logo loaded; no horizontal overflow at checked widths.
- Captures under `.impeccable/review/oauth-consent/` are local review evidence.
  The first details interaction used an unsupported text locator; recaptured
  after clicking the actual summary and confirming its expanded state.
- Both Storybook play functions passed in the rendered browser. The manager
  sidebar exposes all 11 stories, and the preview iframe renders correctly.
- Independent finish review: `ship`, no material fixes. Documentation review
  confirms this is an extension of the incumbent system and requires no design
  context edits. It observed existing missing `.impeccable/design.json` and
  incomplete dark-theme token remaps in DESIGN.md; neither was changed.
- All required root checks pass: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
  `mix deps.unlock --check-unused`. Umbrella seed 42283: 5,226 tests reported,
  zero failures across all applications (configured excluded lanes remain excluded).
  Existing test-only warnings were emitted; production compilation is clean.
- Final browser check confirmed both flow play functions, the full Storybook
  manager/preview link, and no browser exceptions. Server responds HTTP 200 on 6006.
- Sent the requested review-ready notification with `pushnotify` successfully.

## Subsequent review

The user rejected explanatory Storybook copy inside the completion screens.
The final product-copy outcomes, CTA hierarchy, connected-client destination and
website-link changes supersede that initial treatment. See
[the follow-up checkpoint](20261111-2325-connected-clients-preview.md).
