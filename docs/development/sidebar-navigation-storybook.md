# Sidebar and dashboard Storybook review

This is the synthetic UI-state review guide for the implemented
[Console sidebar and dashboard milestone](../../labnotes/milestones/console-sidebar-and-dashboard.md).
Production routing and scoped backend integration are described in the
[UI/API decision](../console-sidebar-navigation.md). User UI review follows
completion; implementation does not imply recorded UI acceptance.

Run `bin/storybook`; use `bin/worktree-port storybook` to find this checkout's port.
Open **Vxpipe → Console → Tenants → Directory** or **Tenants → Dashboard**.
All page stories use the shared sidebar except public authentication, the call
spec editor and call history. Theme controls expose the existing light/dark styles.

## Organization

| Group | Contents |
| --- | --- |
| shared | Sidebar, tenant picker, password fields and role badges |
| Tenants | Directory, My tenants, Dashboard, Create and Getting started |
| Calls | Calls with filter/pagination states; standalone History |
| Call Specs | Call spec directory and sample setup |
| Services | Tenant services, Platform services and tenant inventory |
| API Keys | Tenant key inventory, creation, one-time reveal and read-only states |
| Users | User pages/forms, management journey; components for role selection and tenant access |
| Roles | Role pages/forms; components for permission editing |
| My account | Account page |
| Authentication | Public setup, login and recovery |
| Diagnostics, Samples | Auxiliary page previews |
| Call spec editor | Standalone editor page; inspectors, controls and state demonstrations under components |

The Navigation gallery and duplicate older full journey have been retired.
Each page's existing loading, empty, error, pagination, validation and permission
states live with its owning section. Shared fixture harnesses compose the same
navigation shell as production and suppress the old page headers.

## Review paths

- **Tenants / Directory / Populated**, **Tenants / Dashboard / Single Tenant
  Login**, and **Tenants / My tenants** cover landing and scope states.
- Search/select below Vxpipe; selection opens the tenant dashboard. No reviewer
  instructions are rendered in the rail. Context for a fixture belongs in docs.
- **Calls / Calls** retains the call spec filter, pagination and new-tab inspector
  links; **Call Specs / Call specs** retains row and editor actions.
- Follow user and role forms in **Users / Management journey**. Error, pending,
  protected-account and denied states also have direct page stories.
- Service setup, inventory and API-key states include their dialogs, permission
  variations and clear Services/Platform Services titles.
- At phone width, Menu opens the modal drawer. Search and Escape work within it.
- Call history and the call spec editor remain standalone, with working return links.

Example IDs: `vxpipe-console-tenants-directory--populated`,
`vxpipe-console-tenants-dashboard--dashboard`, `vxpipe-console-calls-calls--filtered`,
`vxpipe-console-services-platform-services--platform-configured`.

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


The October tenant review consolidates Directory and My tenants on the production
list component. Setup overview / Demo nudge and the duplicate All Tenant Login
story are removed. **Tenants / Create** has normal, denied, creation-error, pending
and metadata-only role fixtures. Submit the form in error/pending fixtures to
exercise that state. Creation lands on Dashboard. Rows show name and created age; Services is accessed
through the sidebar when permitted. Dates are fixture timestamps, not production records.

The populated Calls story also demonstrates the searchable call-spec picker,
merged Call info column, local date/time and finalized durations. Storybook uses
tenant fixture search with the production pagination contract; the application
uses `/admin/api/tenants/:key/calls/spec-options` for storage-backed search.

### Tenant API key inventory

API Keys is a separate tenant sidebar item immediately below Services. The
Storybook inventory lists key names and masked values with the final four
characters visible. Creating a key returns to the inventory and shows a
dismissible one-time copy panel; there is no call-spec continuation button.
Sidebar navigation retains tenant-scoped fixture metadata and discards the
secret reveal. These fixtures do not issue or persist production API keys.

The inventory story is `vxpipe-console-api-keys--existing-api-key`.
