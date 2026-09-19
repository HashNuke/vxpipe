# Tenant onboarding: services, API keys and call specs

The [platform and tenant services follow-up](platform-and-tenant-services.md) records
the 2026-09-19 scope decision, Storybook changes and backend implementation sequence.
It supersedes tenant-only credential ownership where explicitly stated. Production
AI/speech inheritance and scoped Console management are implemented; the new scoped
Telnyx webhook routes remain planned. The older Demo onboarding entry now reads
effective services and opens the scoped setup page for credential changes. This does
not claim production integration of the full three-step recipe flow below.

Decision: 2026-09-18. The user approved this direction for Storybook review.
Production integration of the revised flow is a separate checkpoint.

## Flow

1. Create or resume a tenant. The default display name is **Demo**, while its
   durable identity remains independent of its name. Existing names are preserved.
   On the tenant directory, **New tenant** asks only for a name. Successful
   creation immediately opens service setup for that tenant; an error keeps the
   name in the dialog for retry. This setup page applies to every tenant.
2. Use **Setup services** as the primary heading, **AI providers** and **Telephony**
   as section headings, and a smaller tenant-created success alert with a check icon,
   tinted background and visible border; put the setup/rename description inside
   that alert. Connected-service cards have a clear Connected status, provider
   identity and capability tags, plus a separate outlined Manage button. Group them
   under **AI providers** and always-visible, optional **Telephony**. Each grid ends
   with a **Connect a service** card, including when empty or all catalog services
   are connected. Each section also has a Connect a service button beside its
   heading. On mobile, show that button only once the section has a saved service;
   its add card remains available in the empty state. Do not show recommendations
   for unconnected services.
   The card opens a modal with a **Service** dropdown scoped to its section.
   Selecting a service displays its credential fields below the dropdown. Switching
   services clears the previous draft; selection is disabled during validation.
   Both service groups use three columns on desktop and one on mobile.
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

All tenants share “Tenant created: {name}” and “Connect AI and Telephony
services to get started. You can rename this tenant later.” The breadcrumbs and
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

## Speech-to-speech preview boundary

The ordinary provider catalog remains accurate to implemented integrations. Dedicated
`SpeechToSpeechPreview` and `SpeechToSpeechConnectedPreview` stories inject a future
Google speech-to-speech capability into a local catalog fixture. This is a design
preview, not a new runtime provider, a supported model identifier, or a claim that
current Google credentials unlock realtime audio in production. The credential
form uses dummy values and sends nothing upstream. Per-recipe alternatives and
provider/model availability must be resolved server-side during production wiring.

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

The prototype's versioned `setupCatalog.json` separates service capability labels,
convenience `defaultModels`, and supported `sampleCapabilities`. The onboarding
picker is limited to Deepgram, Rime, Google AI Studio and Telnyx. Vertex AI,
Zenmux and Twilio are deferred from this UI (`availableInSetup: false`); their
catalog entries and saved defaults remain available for future integration.

Deepgram, Rime and Google AI Studio ask for an API key. Telnyx asks for an API key
for API calls and an optional public key for webhook validation. The public key
is required for telephony, not AI-only use. When supplied, it must be a base64
Ed25519 public key of 32 bytes. The prototype uses one Telnyx connection in both
sections: AI shows Connected after an API key is saved; Telephony shows Public key
needed until the public key is also configured. Editing either card updates the
same connection. Updating an API key without re-entering a previously configured
public key preserves that configuration; this form does not revoke keys.

The shared credential form exposes the public-key field only when the onboarding
modal opts into it. Production credential APIs are not changed by this prototype.
Raw keys are discarded after simulated validation; only connection metadata and
a public-key-configured flag are retained for the current Storybook session.

Rime exposes TTS ([Rime API-key documentation](https://docs.rime.ai/docs/lovable)).
Telnyx belongs to AI and telephony groups; its AI labels cover
[STT](https://developers.telnyx.com/docs/inference/audio-language-models),
[LLM](https://developers.telnyx.com/api/inference/inference-embedding/chat-public-chat-completions-post/)
and [TTS](https://developers.telnyx.com/api-reference/text-to-speech-commands/generate-speech-from-text).
Its [public key verifies webhook signatures](https://support.telnyx.com/en/articles/4334722-how-to-leverage-webhooks).

Current onboarding sample mappings use Deepgram for STT/TTS and Google AI Studio
for LLM. Rime, Google speech and Telnyx AI runtime adapters remain future work.
A capability counts toward sample readiness only when listed in
`sampleCapabilities` and supplied with a default model. Credential setup alone
does not implement those adapters or complete phone-number routing.

Both Google catalog entries retain STT, LLM, TTS and speech-to-speech labels.
Google documents [Gemini transcription](https://ai.google.dev/gemini-api/docs/transcribe),
[Vertex transcription](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/samples/googlegenaisdk-textgen-transcript-with-gcs-audio),
and [Gemini TTS through AI Studio and Vertex](https://docs.cloud.google.com/text-to-speech/docs/gemini-tts).

Both Google entries store these user-selected defaults:

- STT: `gemini-3.5-transcribe-live`
- LLM: `gemini-3.8-flash`
- TTS: `gemini-3.1-flash-tts-preview`
- Speech-to-speech: `gemini-3.8-live`

Deepgram defaults:

- STT: `flux-general-multi`
- TTS: `flux-hannah-en`

Default models are convenience selections, not an exhaustive model catalog or a
restriction on explicit choices. They do not establish runtime adapter support.
This explanation belongs in internal configuration/documentation, not UI copy.

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
validation progress/failure, provider outage, partial and complete coverage,
multiple model providers, blocked/ready/loading/failed/installed recipes, tenant
setup nudges, multiple tenants, renamed tenant, Twilio credentials, themes and
narrow layout, plus name-only tenant creation, creation progress/failure and a
fresh non-demo tenant. API-key stories cover both grants, creation, error, one-time
reveal and existing-key metadata; Setup Call Specs is also directly discoverable.
The service modal includes a grouped provider dropdown, inline credential fields,
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
