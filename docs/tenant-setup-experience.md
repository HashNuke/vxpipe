# Tenant onboarding: services, API keys and call specs

The [platform and tenant services follow-up](platform-and-tenant-services.md) records
the 2026-09-19 scope decision, Storybook changes and backend implementation sequence.
It supersedes tenant-only credential ownership where explicitly stated. Production
AI/speech inheritance and scoped Console management are implemented; the new scoped
Telnyx webhook routes remain planned. The older Demo onboarding entry reads effective
services for readiness, but **Manage services** opens the tenant-owned credential
inventory. The standalone production `setup-services` route was retired on
2026-09-21 and redirects to **Services**; tenant UI does not identify or display
inherited platform credentials. This does not claim production integration of the
full three-step recipe flow below.

Decision: 2026-09-18, revised 2026-09-21. The shared service list replaces the
earlier AI/Telephony sections in the Storybook onboarding and production platform
services. Tenant inventory uses the same provider catalog and capability labels.
Provider credentials remain one binding per provider/name/scope; telephony
applications reference a binding rather than storing another secret. No credential
migration is needed, so existing tenant and platform credentials remain intact.
The grouped picker was rejected because a provider can offer both telephony and AI.

## Flow

The following flow remains the approved onboarding/Storybook design; it is not a
second tenant administration page.

1. Create or resume a tenant. The default display name is **Demo**, while its
   durable identity remains independent of its name. Existing names are preserved.
   On the tenant directory, **New tenant** asks only for a name. Successful
   creation immediately opens service setup for that tenant; an error keeps the
   name in the dialog for retry. This setup page applies to every tenant.
2. Use **Setup services** as the primary heading and a smaller tenant-created success alert with a check icon,
   tinted background and visible border; put the setup/rename description inside
   that alert. Connected-service cards have a clear Connected status, provider
   identity and capability tags, plus a separate outlined Manage button. One
   **Connect a service** button beside the heading opens the full installed-provider
   picker. The same list contains every connected provider, including Telnyx.
   Do not show recommendations for unconnected services.
   The button opens a modal with a **Service** dropdown.
   Selecting a service displays its credential fields below the dropdown. Switching
   services clears the previous draft; selection is disabled during testing or saving.
   The cards use three columns on desktop and one on mobile; capability tags wrap
   within each card. The tenant inventory also wraps its capability tags.
   Keep capability tags on connected cards; omit capability checklist cards and
   the bottom readiness message. Continue enables for supported speech-to-speech
   or the speech-to-text + LLM + text-to-speech combination; connecting telephony
   alone does not complete voice setup.
3. The second step, **Create API Keys**, offers a named tenant key with **Create & Join Calls** or
   **Full Access**. Show its value once, provide a copy action, then retain only
   metadata when returning. Creating a key is optional for continuing the operator
   setup flow; backend API callers need the appropriate credential.
4. The third step, **Setup Call Specs**, offers sample recipes. Recipes remain
   readable when services are incomplete, with disabled Load actions and an
   explicit link to the missing services. Each recipe declares its own alternatives:
   the voice-conversation preview accepts either voice setup; existing handoff recipes
   require the separate speech/language pipeline. No sample content is on the service page.
5. Show the chosen providers/models before the recipe handoff. Launching a real
   call will remain an explicit action in the existing debug console.

All tenants share “Tenant created: {name}” and “Connect services to get started.
You can rename this tenant later.” The breadcrumbs and
step navigation use **Setup services → Create API Keys → Setup Call Specs**.
Use that navigation to revisit steps; omit redundant Back buttons inside the
step content. Keep the forward Continue actions.
This supersedes the earlier Demo-specific welcome and two-step flow.

The tenant directory shows a prominent continuation card when Demo is the only
tenant and its services or samples are incomplete. With multiple tenants, each
row indicates missing capabilities or missing samples. A services-ready tenant
resumes at API keys, or call specs when it already has a key. Tenant existence alone never establishes voice
readiness, and navigation must not reset another tenant's progress.
Once voice services are configured, onboarding does not require a sample call
spec or a telephony provider. Sample recipes remain an optional next step.

## Speech-to-speech boundary

No current provider declares speech-to-speech support. Setup does not offer it or
count it toward sample readiness. The earlier design-preview stories were removed
when Setup was aligned with implemented integrations. Per-recipe requirements still
allow this capability to be added when a real runtime integration exists.

## Tenant API-key permissions

The implemented `admin` and `calls` grants are independent. Create & Join Calls uses `calls`;
Full Access explicitly includes both `admin` and `calls`. The Calls grant
allows preparing calls, participant sessions/join tokens and tenant call reads.
Full Access adds the tenant administration grant. Neither choice grants
installation/platform authority or another tenant's access.

Evidence: `Vxpipe.Calls.Administration.authenticate/4` checks exact membership;
`Admissions`, `Inspections`, `CallReadAccess` and `BillingEnrichments` check `calls`.
The Gateway authenticates call admission with that same scope. The existing
trusted issuance command accepts a name (up to 256 characters) and explicit grants,
returns the plaintext once, and persists only a digest. See
[tenant control-plane operations](tenant-control-plane.md).

The `admin` grant is not evidence that every tenant-management HTTP endpoint
exists. Current issuance/revocation remain trusted OTP/CLI operations. Storybook
does not add such endpoints or broaden the installation operator's authority.
The proposed labels describe the supported grant combinations without promising
unimplemented administrative APIs. Values shown in the prototype begin with
`storybook-only` and cannot authenticate.

## Providers and models

Setup uses the authenticated binding-directory response's `provider_capabilities`
from `Vxpipe.Providers.Registry` to show registered credential providers and their
implemented STT, TTS and telephony capabilities. The frontend catalog supplies
display names, descriptions, and current sample defaults. Deepgram, Rime, Google
AI Studio, Zenmux, Telnyx and Twilio are available today. Vertex AI is not offered.
Google and Zenmux model inference uses the separate shared ReqLLM runtime.

Deepgram, Rime, Google AI Studio, Zenmux and Telnyx ask for an API key. Twilio
asks for an Account SID and auth token. Telnyx additionally accepts a public key
for webhook validation. When supplied, it must be a base64 Ed25519 public key of
32 bytes. Telnyx appears once in the service list, with a Public key needed indicator
until the key is configured. Updating its API key without re-entering a saved
public key preserves that configuration; this form does not revoke keys.

The shared credential form exposes the public-key field only when the onboarding
modal opts into it. It presents **Test credentials** and **Save** as separate actions.
Testing is read-only and retains the draft for correction or saving. Save remains
available when credential testing is unsupported. Storybook callbacks simulate those
operations; the production contract is documented in
[Provider credential testing and storage](provider-credential-validation.md).

Rime currently supports credential storage and testing only. Setup does not show
an unsupported capability badge. Google AI Studio offers LLM, while
Deepgram offers STT and TTS. Telnyx and Twilio offer telephony. Provider product
features do not appear as Vxpipe capabilities until integrated.

Current onboarding sample mappings use Deepgram for STT/TTS and Google AI Studio
or Zenmux for LLM. Rime, Google speech and Telnyx AI runtime adapters remain future work.
A capability counts toward sample readiness only when listed in
`sampleCapabilities` and supplied with a default model. Credential setup alone
does not implement those adapters or complete phone-number routing.

Current language-model defaults are `gemini-2.5-flash` for Google AI Studio and
`openai/gpt-5` for Zenmux.

Deepgram defaults:

- STT: `flux-general-multi`
- TTS: `flux-hannah-en`

Default models are convenience selections, not an exhaustive model catalog or a
restriction on explicit choices. They do not by themselves establish runtime readiness.

Telnyx telephony is optional for browser recipes;
carrier credentials alone do not establish number routing or callback readiness.
WebRTC callers can use call specs without a telephony provider. Missing telephony
must never hold up service onboarding or browser sample readiness.

The Google and Deepgram defaults are user-selected; other defaults are mirrored
from the existing Calls implementation. This is not a live upstream model directory. When multiple LLM services are
connected, selection is explicit. Saving another credential does not silently
switch that selection. Production sample generation must resolve and validate
the catalog server-side, retain pinned selections in installed call specs, and
preserve operator edits. The browser catalog is not an authorization boundary.

## Alternatives and implications

- Rejected a permanent redirect whenever setup is incomplete: operators still
  need to browse and create tenants. Use resumable setup entry points instead.
- Rejected an always-visible credential form alongside samples: provider modals
  focus credential entry, and a separate sample screen keeps the next action clear.
- Rejected a fixed three-capability checklist: it incorrectly blocks an alternative
  speech-to-speech setup. Keep capability tags on providers and derive Continue availability from supported capabilities.
- Rejected treating any saved credential as complete setup: derive readiness from
  supported model capabilities and distinguish validation from a successful call.
- Rejected silent provider switching and automatic sample replacement: choices
  must be visible, while repeat installation preserves durable identity and edits.

The small setup components reuse the existing admin shell, credential form,
provider marks and design tokens. No additional client application is introduced.

## Storybook implementation

`vxpipe_console/Onboarding` includes service selection, modal entry,
credential test/save progress and failure, provider outage, partial and complete coverage,
multiple model providers, blocked/ready/loading/failed/installed recipes, tenant
setup nudges, multiple tenants, renamed tenant, Twilio credentials, themes and
narrow layout, plus name-only tenant creation, creation progress/failure and a
fresh non-demo tenant. API-key stories cover both grants, creation, error, one-time
reveal and existing-key metadata; Setup Call Specs is also directly discoverable.
The service modal includes one provider dropdown, inline credential fields,
credential clearing on selection changes and keyboard focus restoration. Dialogs
use a visible theme border, solid surface, shadow and a darkened backdrop.
The three recipes are voice conversation, agent handoff and human
handoff with a separate support seat.

Use dummy credentials. Validation is simulated; the story does not send credentials,
persist tenant state, install call specs, request microphone access or start calls.
Its state survives navigation inside a story but resets when the story is reloaded.
The recipe dialog previews provider/model choices, then links to the existing
synthetic debug-console story. That fixture does not consume the chosen recipe.
The new pages are not yet wired into `/admin`; the production changes in this
checkpoint are the default Demo name and related copy.

## Verification

- [x] Red/green behavior tests cover modal focus, capability coverage, blocked
  recipes, explicit model choice, tenant resumption, samples-ready navigation,
  name-only creation and independent new-tenant progress.
- [x] Red/green tests cover the three-step order, generic tenant copy, both key
  grant combinations, clearing the revealed value on navigation and per-tenant metadata.
- [x] Red/green Calls test verifies the new default display name; the Console
  endpoint test verifies that the workflow requests that name.
- [x] Rendered Chrome inspection covers desktop, tablet, mobile, dark/light,
  credential dialogs and keyboard focus, sample cards and error states.
- [x] Red/green tests cover dropdown selection, provider-specific credential fields, persistent last-position add cards, section-specific connections, optional telephony and recipe-specific audio readiness.
- [x] The 2026-09-21 replacement has red/green tests for one picker, one Telnyx
  binding/card, ungrouped provider selection, page-level save feedback, tenant
  inventory capability tags and mobile tag wrapping. Rendered Chrome inspection
  covered desktop/mobile onboarding and tenant inventory plus mobile toast.
- [x] Final frontend/build and umbrella checks recorded in
  [initial checkpoint labnotes](../labnotes/20260918-1812-refine-onboarding-storybook.md)
  and [three-step checkpoint labnotes](../labnotes/20260918-1938-refine-onboarding-key-steps.md).
  The compact picker follow-up is recorded in
  [service-picker labnotes](../labnotes/20260918-2022-compact-service-picker.md).
  The subsequent dropdown and visible-telephony correction is recorded in
  [follow-up labnotes](../labnotes/20260918-2049-show-optional-telephony.md).
  The per-section add cards and footer-copy removal are recorded in
  [grouped-services labnotes](../labnotes/20260918-2109-group-service-cards.md).

Local design review: the dependency direction is unchanged. The prototype can be
reviewed before adding tenant-specific persistence/readiness APIs or altering
production routing. Existing platform-authority, publication and demo-mode gates
remain open in their milestones; this checkpoint does not claim those contracts
are implemented.
