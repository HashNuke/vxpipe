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

## Alternatives and implications

A mutable graph compiled into JSON was rejected because it could lose fields and
change source digests on a no-op save. Persisted layout metadata and automatic
legacy migrations were rejected for the same reason. Frontend provider/model
inventories and hard-coded wire formats were rejected because they could drift
from installed adapters.

No React, transport, persistence or live-provider operations belong in this layer.
It can be tested without rendering. Browser verification belongs to the later
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
