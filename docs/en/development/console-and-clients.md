---
title: Console and client development
description: Phoenix hosting, React routing, portable editor state and browser client boundaries.
sidebar:
  order: 8
---

## Host and routing

Console owns Phoenix Endpoint, browser identity, CSRF, HTML shells and built
assets. Gateway is mounted in the same request pipeline for product APIs,
MCP and media signaling. Browser helpers do not create a second business-logic
implementation beside the canonical `/api` operations.

The React application uses `createBrowserRouter`/`RouterProvider`. React Router
owns path matching, redirects, parameters and browser history. Keep pagination,
filters and directory search in URL state. Cancel or ignore superseded requests;
Back/Forward must restore the selected view without stale data winning a race.

Canonical pages include `/getting-started`, `/tenants`, `/t/:tenant_key/calls`,
`/t/:tenant_key/call-specs`, `/t/:tenant_key/services`, `/users`, `/roles`,
`/api-keys` and `/platform/installation`. The current route table is in
[`App.tsx`](../../../apps/vxpipe_console/assets/src/App.tsx); Phoenix must serve
its document on direct loads of every supported client route.

The voice playground has its own `/admin/samples` router, with
`pipecat-console` and `transfer` children. Navigation stories simulate workflows;
their controls are not proof that a production route starts calls.

## Editor source is authoritative

Framework-free editor functions hold the portable call-spec source. Canvas,
selection and inspector state are projections; saving serializes only source.
Preserve omitted fields, explicit nulls and supported advanced options when
editing unrelated fields. A read-only historical revision cannot be made
editable by changing a local UI flag.

Participant/variable renames update structural references together: direction,
transfers, routes, permissions and variable-driven destinations. Never search-
replace natural-language prompts. Removing a referenced variable leaves a
validation problem; it does not invent a new phone destination.

Client validation accumulates backend-shaped paths and byte-bound errors.
The backend remains authoritative for credentials, provider options, compilation
and route conflicts. The shared
[editor validation fixture](../../../examples/contracts/call-spec-editor-validation.json)
checks drift for specified cases; it does not make TypeScript a second compiler.

## Client boundaries

`@vxpipe/core` owns framework-neutral call-detail state, revision reconciliation,
host loading and live-control contracts. `@vxpipe/react` renders an injected Core
controller. Neither package chooses a Console URL, performs login or owns tenant
credentials. Both remain private workspaces; published npm/shadcn delivery is
separate work.

The Console host fetches the authorized inspection snapshot, validates it and
maps snake-case JSON into Core's TypeScript model. Unavailable data has an explicit
reason; it is not substituted with an empty transcript, zero usage or a fake result.
Newer revisions replace corresponding entities by stable identity. A persisted
baseline and live updates must reconcile by sequence/revision, not receipt time.

For web admission, a backend prepares a call and issues a participant join token.
The client redeems it at
`POST /api/tenants/:tenant_key/calls/:call_id/participants/:participant_key/sessions`.
The resulting Gateway session owns subsequent signaling/connection authority.
The playground uses Pipecat/RTVI and `/api/rtvi/offer` for negotiation; it does not
expose a server API key to the browser. Treat tokens and session credentials as
secrets, never navigation parameters.

The database-backed inspection host and the live playground have different
capabilities. A read-only snapshot renderer must not show active controls merely
because the call is marked ongoing. Full reusable live-control integration
remains tracked by the debug-console milestone.

## Components and styles

Keep component layout/state styling close to TSX, using Tailwind v4 utilities and
semantic CSS variables. Package-owned styles cover theme/base rules and necessary
keyframes. The intended npm CSS artifact and source-installable registry must
derive from the same components; do not maintain two UI implementations.

Use the current component primitives for dialogs, searchable pickers and errors.
Unknown backend paths remain visible in an issues list. Save/test/authorization
errors are distinct states; closing a dialog must not silently submit or lose a
working saved connection. Credential inputs clear after terminal submissions.

Integration browsing joins public listings with local state; a remote page cannot
decide whether an account is connected. OAuth restores only matching nonsecret
draft/navigation state. Mobile layouts retain reachable controls and bounded
dialog scrolling.

## Verification

Root Storybook discovers Console and package-owned stories. Run `npm run storybook`
for component work. Synthetic microphone/tool controls are previews, not network
acceptance. Inspect actual production UI changes in a rendered browser at desktop
and mobile sizes, including keyboard focus, direct routes, history, loading,
permission denial and failure recovery. See [Testing and verification](testing.md).
