# Reconcile admin scope

## Problem

The active Storybook milestone ended with a definition-specific Calls page and final approval gate.
Later product direction requires every resource page to be tenant-scoped, with sibling Call
definitions, Calls and Services destinations. Calls must optionally filter by definition so a
definition can deep-link into the tenant call directory. Services must let an installation operator
add provider credentials.

The existing production-integration milestone repeated the older four-page information architecture,
so changing only the Storybook plan would leave the approved page contracts without downstream
query, endpoint and routing checkpoints.

## Decisions

- Add shared tenant workspace navigation with the tenant Calls page so the checkpoint has no dead
  destinations. Add Services to that navigation only with its complete page.
- Replace the eventual definition-specific call route with tenant Calls at
  `/admin/tenants/:tenant_key/calls` and an optional `definition_id` query filter. Call details keeps
  `/admin/tenants/:tenant_key/calls/:call_id`.
- Use explicit sibling routes for `/definitions`, `/calls` and `/services`; the tenant root is an
  entry redirect to Call definitions.
- Split tenant Calls and Services into separate runnable Storybook checkpoints. Final journey review
  moves after both.
- Scope Services to contracts Vxpipe already supports: Google, Zenmux, Deepgram, Telnyx and Twilio.
  Existing secret values are never rendered or returned. Operators may add credentials; revealing
  or replacing credentials, introducing providers/auth methods and imposing third-party rotation
  schedules remain excluded.
- Credential setup is create-only. The existing tenant/provider/name uniqueness contract reports a
  duplicate conflict and never overwrites. Production integration must expose this through a new
  bounded Calls-owned installation-operator mutation rather than calling the trusted-host-only API
  or Persistence from Console.
- Keep telephony public service configuration distinct from its write-only credential fields.
- Existing telephony metadata is read-only in this milestone. Creating a Telnyx/Twilio credential
  neither registers a telephony service nor proves provider readiness; the UI distinguishes stored
  credentials from configured/verified/ready service status.
- Mirror each new Storybook checkpoint in the later authenticated production-integration milestone.

## Rejected alternatives

- Keeping one page per definition would duplicate the call directory and make “all tenant calls” a
  different page contract.
- Encoding the definition filter only in component state would break deep links, refresh and browser
  history.
- A generic arbitrary provider form would imply support the runtime does not have and weaken field
  validation.
- Masked placeholder secrets were rejected because they suggest the browser received a stored value.

## Verification

- The Storybook milestone now has seven checkpoints: four complete slices, tenant workspace/Calls,
  Services credential setup and final user review.
- The milestone index reports 4 of 7 complete.
- The production milestone has matching tenant navigation, Calls and Services checkpoints and keeps
  authentication outside Storybook.
- Independent GPT 6 Astra xhigh review cleared the reconciled plans after the create-only authority,
  no-dead-link sequencing and read-only telephony service distinctions were made explicit.
