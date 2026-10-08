# Call spec editor source model

## Decision

The framework-free editor modules under Console assets hold the portable source
itself. Parsing preserves optional fields, explicit nulls, provider options and
legacy concrete model IDs. Serialization sends only this source; the graph and
inspector state are separate projections. Historical schema `20260915.01` opens
read-only and cannot be edited by changing the document's read-only flag.

Participant edits clone the source and update structural references together:
direction, transfers, audio/transcript route keys and recipients, and visibility
overrides. Variable section and field renames update grants, required fields and
phone-number references. Literal prompts and descriptions are never searched or
rewritten. Removing a referenced variable leaves an empty required selection so
validation asks the operator to choose a replacement. It never substitutes a
fixed phone number or changes a transfer destination silently.

Switching to outgoing requires an explicit phone service and an agent handler.
Switching back seeds an incoming web connection. Both keep the entry participant
key and explicit first-message choice; each direction's omitted first-message
behavior remains owned by the backend. Capability overrides can be removed to
inherit defaults, and omitted wait slots remain distinct from explicit silence.

The new-spec seed matches the development example: an incoming web caller and a
text-capable agent. It uses Google's catalog recommendation when installed, or
the first available language-model provider in deterministic order. The model ID
always comes from the catalog. Voice capabilities are explicit additions. Public
speech options and voice parameter names also come from adapter descriptors;
Deepgram STT declares its required encoding/sample rate, and Flux TTS retains a
separate voice. Existing source is never reseeded when opened.

## Validation and presentation

Client validation accumulates independent problems using backend JSON paths and
UTF-8 byte limits. It validates structural source rules, references, direction,
phone numbers, tools, variables, media and visibility policies. Runtime-specific
provider options, credential availability, telephony routing and compilation
remain authoritative backend checks; the client does not duplicate adapters.

A shared fixture in `examples/contracts/call-spec-editor-validation.json` is
executed by Call Engine and Console tests. Each invalid case specifies the
backend's first error path; the accumulating client must include that path.
Boundary cases must pass both. This is a drift check for the listed cases, not a
claim that the TypeScript validator implements every backend compiler decision.

Error presentation maps paths to a canvas node or Call settings, inspector tab,
field and operator label. Unknown paths retain the backend reason in the issues
list. Save/publish feedback distinguishes validation, missing services, conflict,
permission, expired session and retryable failures. These pure functions return
presentation data; the UI owns focus, badges, toast replacement and dismissal.

## Inspector edits

Call settings composes standard form controls over the source-edit functions.
Typed option fields support JSON scalars, arrays and nested objects; operators
never need to edit raw JSON. Removing the last key retains an explicit empty
object, while Clear omits the optional object. Voice parameters are edited by the
catalog-driven voice field and reserved against collisions in the other options.
Changing provider replaces the whole selection with that provider's recommendation;
changing model preserves the provider's credential name and provider_options while
resetting model options to the descriptor's defaults.

Variable rows belong to named sections. Their type, nullable flag, required
membership, enums, nested object fields, array items and supported constraints are
editable independently. Controls expose constraints appropriate to the selected
type, plus any unusual constraints already present in the source. They do not
normalize away stored keywords. A section permission matrix includes obsolete
grants so the operator can clear a reference to a missing section; it cannot grant
new access to a missing section. Section and top-level field renames still use the
source functions that rewrite permissions and dial references atomically.

Entry and human inspectors edit the same participant records. Changing connection
service applies the selected role's admission rules and removes phone-only fields
when switching to web. An outgoing callee uses a fixed number or the outgoing
request's `to`; transfer destinations also support a declared string variable.
Saved connections are not normalized on load. Opening text has an explicit TTS
selection, independent of participant defaults. Clearing optional descriptions or
private briefings removes the field; opening a saved null leaves it unchanged.
Participant capability panels show the call default and any explicit override.
The human inspector's transfer timeout edits the one call-wide transfer policy.

The Agent inspector keeps omitted first-message and transfer-history defaults
implicit. Changing either mode replaces its dependent fields in one edit. Its
transfer picker and canvas share the eligibility rule, and existing invalid
references remain removable. Tool editing preserves per-tool visibility across a
key rename, rejects reserved keys and collisions, and keeps host keys equal to
their registered tool names. MCP integration names come from lookups; tool names
are entered explicitly and resolved by the backend. The tool dialog holds its
draft locally until Add or Save, so Cancel does not change the source.

## Issue presentation boundary

Client validation and the last field-related server error remain separate. The
header counts client issues; node and tab badges use the merged, deduplicated
field issues. Backend failures persist across unrelated edits and unsuccessful
retries, and clear when their source value changes or a save succeeds. Late
responses are compared with the submitted source before attaching a field error.
Network, conflict, session and authoring-permission outcomes never become field
issues. Secret-material errors use client-owned text rather than the server reason.

Rendered inspectors register source paths in an issue scope. The scope assigns an
error to its exact control, nearest represented collection, or visible-tab summary.
A dialog takes precedence over an underlying card with the same path. Show requests
carry an identifier so normal edits do not steal focus; tool dialogs and collapsed
constraints reveal their controls before focus moves. Global DOM selectors alone
were rejected because hidden tabs, portals and duplicate paths make them ambiguous.

The JSON view serializes the current portable source without normalization. It is
read-only and exports the same bytes through copy and download. Existing Console
toasts provide action feedback with an optional standard Button; their success
expiry and persistent failure behavior are reused. The full editor connects these
components to request handling, selection and recovery. Show selects the source's
node and tab and opens the phone inspector; unmapped issues stay in the drawer.

## Draft and request lifecycle

The editor reducer keeps the current portable source and the last successfully
saved source separately. A request captures its submitted source. Save success
advances the saved baseline and revision metadata to that snapshot, preserving
any edits made while the request was pending. Replacing the current document on
success was rejected because it would silently discard those later edits. Publish
targets a saved, unchanged revision; success marks that revision as published even
if the operator starts the next draft while publication is pending.

An injected transport runs outside the pure reducer, allowing the same lifecycle
to drive the Storybook prototype before production wiring. Client errors prevent
requests, concurrent clicks cannot start duplicate writes, and failed requests
retain both source and baseline. Retry submits the current draft. Explicit reload
aborts pending work and preserves a monotonically increasing request ID so late
responses cannot attach to the replacement document. Unmount aborts requests and
suppresses late session-expiry notifications. The editor confirms Back, Open
services and Reload when changes would be lost, and installs a browser-unload
guard. The host supplies navigation and reload transport; production router
blocking remains part of W. No expected-revision parameter is invented: the existing Calls
save workflow allocates and appends immutable revisions.

Incomplete success metadata produces retryable feedback without claiming a save.
The transport adapter will still validate response shapes at the production API
boundary. The copied inspector dispatcher selects the existing settings, Entry,
Agent and Human panels; transfer edges expose their endpoints and deletion, while
the Entry edge stays locked. Adding a participant opens its inspector on phones.
Rename and tool failures retain their local field drafts and replace the editor's
notification. Failed reload keeps the current document; recovery actions are
disabled during a write or reload so an old notification cannot start concurrent
recovery. Invalid-request defects log only the action name and a fixed message.

The full-page stories use injected outcomes through the real editor lifecycle,
rather than pre-rendering an outcome in disconnected components. Loading and
spec/catalog failures use page states with Retry; they do not create action toasts.
The full editor and stories have passed their build and rendered verification;
the prototype is ready for the milestone's user review.

## Alternatives and implications

A mutable graph compiled into JSON was rejected because it could lose fields and
change source digests on a no-op save. Persisted layout metadata and automatic
legacy migrations were rejected for the same reason. Frontend provider/model
inventories and hard-coded wire formats were rejected because they could drift
from installed adapters.

No React, transport, persistence or live-provider operations belong in the pure
source modules. They can be tested without rendering. Browser verification belongs to the later
inspector and production integration checkpoints. The backend still validates
every save and publish; client acceptance never grants authoring authority.

## Verification

Focused red runs preceded source parsing, graph projection, participant and
variable edits, validation, error placement, seed and public option defaults.
The shared backend fixture covers required fields, byte/range boundaries,
references, direction, tools, variables and policies. Separate tests cover all
example round-trips, legacy read-only behavior, immutable edits, public model and
voice separation, and every save/publish outcome in the milestone. Execution
counts and full-suite evidence are recorded in the implementation labnote.

The full editor prototype now composes these boundaries in 34 page stories.
The frontend lane passes 491 tests, TypeScript and lint; the Storybook production
build and all five root gates pass (3,448 tests, zero failures, seed 991936).
Rendered checks cover all page stories at desktop and phone widths, recovery
confirmations, field navigation, clipboard feedback and downloaded JSON.
Production endpoint/router integration awaits the milestone's user review gate.
