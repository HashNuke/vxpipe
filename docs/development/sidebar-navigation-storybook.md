# Sidebar and dashboard Storybook review

This is the synthetic UI-state review guide for the implemented
[Console sidebar and dashboard milestone](../../labnotes/milestones/console-sidebar-and-dashboard.md).
Production routing and scoped backend integration are described in the
[UI/API decision](../console-sidebar-navigation.md). User UI review follows
completion; implementation does not imply recorded UI acceptance.

Run `bin/storybook`; use `bin/worktree-port storybook` to find this checkout's port.
Open **Vxpipe → Console → Navigation → Pages**. Start with **Dashboard**
(`vxpipe-console-navigation-pages--dashboard`). All stories expose light/dark themes.

## Review paths

- **All Tenant Login**, **Single Tenant Login**, **Multiple Tenant Login**, and
  **No Tenant Access** model the four landing outcomes from `/`.
- Open the tenant picker directly below Vxpipe, search by name/key, use arrows and
  Enter to choose a tenant. It opens that tenant's dashboard. Its footer returns
  to Tenants or My tenants. Switch tenant again from a resource page.
- Follow Calls, Call Specs, both Services links, Users, Roles and My account.
  Open user/role creation, details and password reset; local back links and forms
  remain in the new shell. New tenant opens the existing creation dialog.
- **Mixed Permissions**, **Read Only Member**, **Api Key Only Services**,
  **Read Only Api Keys**, **Read Only Platform Services**, **Read Only Tenant Services**
  and **Read Only Legacy Services** demonstrate resource-specific visibility.
- Review **Getting Started**, **Api Keys**, **Sample Call Specs**, **Legacy Services**,
  **Diagnostics**, **Voice Sample**, and **Transfer Sample** for auxiliary header
  treatment. Diagnostics and voice/transfer show synthetic offline/pre-call layouts;
  they do not reproduce a running LiveView collector or live media session.
- **Call Spec Editor** and **Call History** remain standalone. The call-spec list
  opens the editor; call records open the existing inspector fixture in another tab.
- At phone width, Menu opens the same navigation in a modal drawer. Escape closes
  it; the tenant picker remains searchable inside the drawer.
- Loading, unavailable, retry, empty dashboard and tenant directory stories cover
  failures without replacing them with invented metrics. Picker controls expose
  loading/unavailable states; unmatched search shows No matching tenants.

## Mock boundary

All accounts, tenants, calls and service states are synthetic fixture data. No
provider or backend requests are made. Login accepts a nonempty fixture form;
password verification, server redirect decisions and revocation belong to the
production implementation and are not exercised by this mock. Fixture API keys are nonfunctional.
Never enter real credentials in Storybook.

Storybook navigation uses hashes to model browser destinations. Embedded authentication forms use mock routes; production canonical URLs are
defined in the decision document. Refresh/Controls reset fixture
changes; switching between separate page modules may reset their local mock data.
Directory and picker search operate on a small permission-filtered fixture list.
Production search/pagination and fresh principal checks run server-side.
The inspector uses existing synthetic call details, not a live subscription.

## Storybook checkpoint evidence

The full page inventory and API ownership review live in the decision document.
Chrome inspection covered 49 desktop/phone and light/dark captures, followed by a
bounded correction pass for the mobile dashboard, service footer and permission
variants. No page-level horizontal overflow was observed. Wide Calls/Call Specs
ledgers retain local horizontal scrolling; the dashboard's recent records reflow
with call identity, state and time visible on phones.

Focused tests cover landing precedence, filtered directory/search selection,
mixed scopes, service permissions, logout, standalone exceptions and creation.
The [labnote](../../labnotes/20261013-1023-sidebar-dashboard-proposal.md) records exact
checks, independent review findings and final verification. Engineering review
does not imply user approval. These results describe the earlier Storybook
checkpoint, not the final production verification run.

At the Storybook checkpoint, checks passed: 682 frontend tests, TypeScript, lint, both asset builds and
all five umbrella gates (3,749 tests, no failures). The independent reviewer
scored the reported fixes resolved; the static design scan returned no findings.


## Production review

The production shell uses real canonical links, server-authorized navigation,
paginated tenant search and the scoped dashboard endpoint. Visit `/` with all,
one, many and zero visible tenant profiles, then inspect `/tenants` or
`/my-tenants`, a tenant dashboard, Calls, Call Specs, Services, Users, Roles,
My account, Platform Services and Getting started as permitted. Recheck the
permission-filtered sidebar after changing scope, and preserve a protected deep
link across login. Call-spec editors and call inspectors remain standalone.

Inspect the actual diagnostics page and voice/transfer samples separately from
their fixture stories. Diagnostics mounts navigation in an independent React
island and leaves LiveView DOM ownership intact; phone content begins below
Menu without a viewport-sized spacer. Samples use full-document navigation to
leave their entry point. Production CSS uses a separate Tailwind `admin-ui.css`
output alongside esbuild assets.

The API-key setup and recipe stories demonstrate existing presentation components
only. They do not imply new production routes. Use the production Services
workflow for credential management and Getting started for setup.

The coordinating production browser pass captured desktop and phone dashboard,
directory, scoped-persona, service, diagnostics and sample states. Its captures
are development evidence, not shipping image assets. The milestone and linked
task labnotes own final test counts, rendered review findings and any remaining
limitations; the earlier checkpoint totals above must not be presented as final
production results.
