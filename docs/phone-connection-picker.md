# Phone connection selection

## Contract and ownership

Connection cards offer Web (WebRTC) or Phone for human participants and Entry.
Outgoing Entry remains phone-only. Phone opens a modal with an inline Telephony service dropdown listing Twilio and Telnyx
services; a provider is disabled when the tenant has no configured service for it.
In-use numbers show a muted inline “In use” indicator without the call spec name.
An empty inventory prompts buying a number; an entirely occupied list explains
that no numbers are available for use. Empty search results report no matches.
Without either service, only Cancel and Close dismiss the dialog. Connection
changes are applied on confirmation, preserving the source on cancellation.
Switching to Web removes the phone service, fixed number and variable reference;
the Phone card displays a dash.

Incoming Entry selects an existing account-owned number. Outgoing Entry and human
transfers select the dialing service and keep their existing destination fields
(fixed number, outgoing request destination, or supported variable reference).
The user explicitly approved this distinction. Account numbers are receiving
endpoints; they cannot replace arbitrary callee destinations.

Gateway owns the provider inventory protocol. Twilio.Adapter and Telnyx.Adapter
expose `list_phone_numbers`, backed by each carrier's PhoneNumberCatalog.
Gateway normalizes the result into `{numbers, next_page}`. Calls authorizes the
installation operator, resolves the tenant's private service credential, and
annotates number availability from Persistence. Console exposes:

`GET /admin/api/tenants/:tenant_key/telephony-services/:service/numbers`

Query fields: `search`, optional opaque `page`, and optional `call_spec_id` to
retain this spec's current assignment. The UI receives id, number, name,
`available` and `assigned_to`, plus `next_page`. Credentials, application IDs and
raw provider payloads never enter the browser. Reads use the existing installation
session, tenant boundary and private/no-store response policy.

## Provider APIs

- [Twilio IncomingPhoneNumber](https://www.twilio.com/docs/phone-numbers/api/incomingphonenumber-resource):
  lists owned numbers, filters by PhoneNumber, and follows PageToken pagination.
  Only numbers reporting voice capability are selectable. Page URLs are never
  followed; only the token is carried to the fixed account endpoint.
- [Telnyx phone-number guide](https://github.com/team-telnyx/ai/blob/main/guides/phone-numbers.md):
  lists `/v2/phone_numbers` with page pagination and phone-number search, filtered
  to active numbers on the selected scoped Voice API application. This prevents
  a shared platform credential from exposing another tenant's application numbers.

Requests are read-only, bounded to 50 numbers per page, with no redirects/retries
and a 10-second receive timeout. Number purchasing, automatic webhook reassignment
and provisioning are outside this selection workflow. Twilio webhook configuration
and Telnyx application/number linkage still use their existing service setup paths.

## Published assignment rules

Picker results disable numbers assigned to another currently published spec in
this tenant, across service aliases. A same-spec published number remains usable.
Drafts do not reserve numbers. Server-side search and explicit Load more requests
refresh inventory and assignment state; filtering is not restricted to a local
initial list. Storybook deliberately supplies fixture inventory through the same
loader contract.

Persistence rechecks assignments transactionally during publication, under a
per-tenant row lock compatible with foreign-key reads. This serializes competing
publications, excludes the current spec for replacement revisions and rolls back
on conflict. `phone_number_in_use` returns HTTP 409 with an actionable UI message.
Draft saves remain allowed, including an already assigned number.

Rejected alternatives: listing purchasable numbers, treating owned numbers as
transfer destinations, filtering only an initial browser list, and checking only
in the modal. The latter permits stale selections and concurrent publication races.
Legacy ambiguous publications remain readable for diagnosis; new conflicts are
rejected. Existing directory ambiguity tests now inject historical rows explicitly.

## Verification

Focused tests cover provider protocol requests/normalization/pagination, authorized
inventory and own-spec exclusions, endpoint authentication and secret-safe output,
draft-versus-publish conflicts, cards/modal cancellation, provider disabling,
server-backed search and pagination, disabled used numbers, and Web clearing.
Root and browser acceptance evidence is recorded in the task labnotes.
