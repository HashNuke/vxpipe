---
version: 1
slug: "assets-src-admin-navigation-navigationjourney-tsx"
primary_target: "apps/vxpipe_console/assets/src/admin/navigation/ConsoleNavigation.tsx"
related_targets: ["apps/vxpipe_console/assets/src/admin/navigation/NavigationShell.tsx", "apps/vxpipe_console/assets/src/admin/navigation/NavigationJourney.tsx", "apps/vxpipe_console/assets/src/admin/navigation/WorkspacePages.tsx"]
---

# Console navigation

Mode: Operate. Existing Console users need to choose tenant scope and reach their permitted work. User specified the rail order and standalone exceptions. Code-led extension of the existing DESIGN.md; no visual-world replacement.

## Direction contract

THESIS: One persistent navigation rail anchors tenant work and platform administration.
OWN-WORLD: Existing neutral Operator's Bench, Inter controls, shallow corners, restrained dividers.
STORY: Identify scope, choose tenant, enter permitted work, return to account.
FIRST VIEWPORT: 232px rail; searchable picker below logo; page title and actions above a wide working surface. Recent calls lead the dashboard.
FORM: User-specified sidebar order; local extension, no concept seed required. Code-led extension, now integrated into production.
FINISH: Complete production integration, rendered review, scoped API verification and milestone acceptance. User explicitly authorized full implementation and will review the completed UI. No shipping raster is introduced.

The existing DESIGN.md remains the visual-world baseline. The user authorized the
whole milestone after the Storybook proposal; production adoption is now in review.

## Observed production extension

Production uses `ConsoleNavigation`, `NavigationShell`, `WorkspacePages`, the
server-driven tenant picker, recent-call list and shared navigation stylesheet.
Root `DESIGN.md` and its sidecar now record this implemented extension of the
Operator's Bench. `NavigationJourney` remains a synthetic Storybook harness,
not the production data or authorization source. User UI review is deferred
until completion; implementation authorization is not recorded as UI acceptance.

### Palette, type, and depth

- The shell reuses the light/dark `--admin-bg`, `--admin-panel`, `--admin-ink`,
  `--admin-muted`, `--admin-soft`, and `--admin-line` variables. Selected links
  use the neutral soft fill, stronger text and weight; they do not introduce a
  new brand accent. Existing call-state badges carry state color.
- Inter remains the inherited interface face. Sidebar navigation and supporting
  copy use 13px text; group labels use 12px semibold sentence case. Page titles
  use 24px/1.3 at weight 650, reducing to 22px on phones. Recent-call names use
  14px semibold, increasing to 15px on phones; IDs stay in code elements at
  11px. These administration roles extend the existing workbench type ramp.
- Navigation links use 4px corners; picker and search field use 6px corners.
  Core surfaces remain flat, with one-pixel structural dividers. The temporary
  picker alone adds an ambient shadow (`0 10px 24px #0003`); the mobile drawer
  uses a dark translucent backdrop.

### Layout and responsive behavior

- Desktop uses a 232px sticky rail with its own vertical scrolling and a
  flexible, shrinkable workspace. The rail fills the viewport height. Vxpipe
  sits above the tenant picker; the account region is pushed to the bottom
  when height permits.
- Workspace content is bounded at 1600px, with 36px vertical and 32px horizontal
  padding. A wrapping page-title/action row precedes the working surface.
  Tenant pages also provide a compact linked tenant name and key above the title.
- At 760px and below, the rail gives way to a compact Menu bar and a modal
  drawer capped at 300px or 88vw. Content padding becomes 24px by 16px. The
  drawer's 160ms entry animation is enabled only when reduced motion is not
  requested.
- Recent calls use a continuous list of linked records, separated by top rules.
  Desktop aligns call identity, state, timestamp and external-link icon in four
  columns. Phone records place identity across the full row, then state and time
  below; the decorative external-link icon disappears. IDs wrap inside records.
  The separate Calls and Call Specs ledgers retain their own overflow behavior.

### Implemented interaction contracts

**Scope before destination.** The picker sits directly below the brand and
searches server-authorized tenant pages by name or key, with Load more tenants.
The full directory uses page controls; search changes reset its page. Choosing a tenant
closes the picker and opens that tenant's dashboard. A check marks the current
tenant; the footer opens Tenants or My tenants according to visible scope.
Loading, unavailable with retry, and no search matches are separate picker states.

**Stable permitted order.** Tenant destinations are Calls, Call Specs, Services;
Platform destinations are Tenants, Roles, Users, Services. Permission filtering
removes unavailable destinations and empty groups. Before tenant selection, the
Tenant region prompts the user to select a workspace. My account and Logout
follow the navigation. Selected links expose `aria-current="page"`; nested
resource paths retain their parent selection.

**One working surface per route.** Ordinary administration pages use this shell and
their own title/actions. Dashboard shortcuts precede Recent calls; up to five
recent calls appear when calls access is available. Call records open the
standalone inspector in a new tab, announced in the link's accessible
name. The call-spec editor also remains outside the shell. Login, setup and
recovery show no private navigation.

**Keyboard access follows navigation.** A focus-visible skip link targets the
content. Shell navigation requests focus on that content container; on phones,
the coordinating browser pass observed settled focus returning to Menu after
the modal drawer closes. Links and buttons use a two-pixel semantic focus
outline. The picker
uses Radix Popover and cmdk; the drawer uses Radix Dialog. Its named close button,
modal behavior and searchable picker preserve the same destination order on
phones. These dependency-backed interactions are not a claim of complete
accessibility conformance.

### Production integration and review boundary

Canonical routes cover tenant directories, dashboards and resources, account,
users, roles, platform services and Getting started. Authenticated root landing
uses fresh scope: all tenants leads to Tenants, exactly one authorized tenant to
its dashboard, and zero/many assigned tenants to My tenants. A signed-session
return path preserves a protected deep link across login and is rechecked before
redirect; destination routes still enforce their resource boundaries.

The API provides scoped navigation, paginated tenant search and a bounded recent
call projection. Loading, no access, empty data and unavailable data remain
separate. Abort and tenant identity checks prevent stale results from replacing
current selection. Sidebar hiding is presentation; server authorization owns
access. Existing editor and inspector URLs remain standalone.

Diagnostics mounts navigation into its own React island while LiveView retains
its content DOM. Its desktop rail is fixed, external content is offset by 232px,
and the external host has `min-height: 0`; phone content has no left offset.
Voice and transfer samples reuse the shell with full-document navigation.
Tailwind emits `admin-ui.css` separately from esbuild's `admin.css`; page entry
points load the appropriate asset rather than overwriting one with the other.

The API-key setup and sample-recipe pages in this Storybook journey remain
presentation fixtures; they do not establish extra production routes. Storybook
retains synthetic accounts, hash navigation and local retry transitions. It does
not establish provider interoperability or server authorization evidence.

The coordinating browser pass captured production desktop and phone states,
including scoped personas, services, dashboard, diagnostics and samples. This
documenter inspected the supplied dashboard and mobile diagnostics captures and
source. The milestone and task labnotes own test gates and the final review
verdict; this record makes no assertion that pending checks have passed. No new
raster asset ships with this change, and no user UI acceptance is claimed.
