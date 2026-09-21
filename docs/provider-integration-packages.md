# Provider integration packages

## Decision

Vxpipe groups provider-specific code under `Vxpipe.Providers.<Provider>` and exposes a fixed provider
manifest. A manifest declares only the capabilities that provider supplies. The initial capability
set is credential schema, credential testing, speech to text, text to speech and telephony. Missing
capabilities return an explicit unsupported result; registry lookup never selects another provider.

The shared contract and fixed registry live in a small dependency-light umbrella child. Concrete
implementations stay in the existing umbrella child that owns their runtime dependencies:

- Console owns the bounded HTTP executor used by credential tests.
- CallEngine owns speech session contracts and execution.
- Gateway owns telephony HTTP/media orchestration.

Those modules still use the provider namespace. Elixir module identity gives each provider one
logical package without forcing CallEngine or Gateway to depend on a plugin that itself depends on
their contracts. No provider process, registry process or dynamic module discovery is introduced.

## Contract

Each provider root implements `Vxpipe.Providers`:

```elixir
@callback id() :: String.t()
@callback capabilities() :: %{optional(capability()) => module()}
```

`Vxpipe.Providers.Registry` is the only provider-name registry. It supports exact lookup and reports
`{:error, :unsupported_provider}` or `{:error, :unsupported_provider_capability}`. Its
`resolve_capability/2` also checks that the implementation is installed; a partial library build
returns `{:error, :provider_implementation_unavailable}` instead of calling an absent module.
Internal modules may live under the provider directory without appearing in the manifest.

For example, Deepgram's manifest declares `:credential` and `:credential_validation` modules in
`vxpipe_providers`, plus `:stt` and `:tts` session modules in CallEngine. Its sockets are private
implementation modules, so they are not additional manifest entries. Telnyx and Twilio declare
`:telephony` service profiles; their HTTP handlers and media sockets stay private to that capability.

The provider credential contract is small: `auth_kind/0` declares the stored auth kind and
`validate/2` checks its exact, bounded payload shape. Optional `credential_validation` implements
`request/2`, returning a pure request description or
`{:error, :provider_validation_unsupported}`. Console owns the bounded HTTP execution and response
classification; a provider module does not make a network request or store a credential. Unsupported
provider/capability lookup sends no request. Save uses the schema independently of Test credentials.

Capability presence and runtime readiness are different facts:

- **unsupported** — the manifest has no capability entry;
- **supported** — the manifest names an implementation;
- **configured** — the requested scope has locally valid configuration and credential bindings;
- **ready** — the owning runtime completed its existing startup/readiness contract.

Credential testing is optional and does not determine whether another capability may be configured.
Model inference remains the shared ReqLLM integration. Provider manifests do not duplicate ReqLLM;
Google and Zenmux model support continues through the agent-runtime catalog.
The Console's authenticated service-binding response includes `provider_capabilities` from the
fixed registry. Setup offers only registered credential providers and intersects speech/telephony
badges with that response. Google and Zenmux LLM labels remain explicit Console metadata for the
shared ReqLLM path. See the [setup catalog decision](issues/setup-catalog-runtime-capabilities.md).

## Existing provider manifests

| Provider | Credential schema | Credential test | STT | TTS | Telephony |
| --- | --- | --- | --- | --- | --- |
| Deepgram | yes | yes | yes | yes | no |
| Google AI Studio | yes | yes | no | no | no |
| Telnyx | yes | yes | no | no | yes |
| Rime | yes | yes | no | no | no |
| Twilio | yes | yes | no | no | yes |
| Zenmux | yes | yes | no | no | no |

The table describes Vxpipe-owned provider capabilities. ReqLLM model support is deliberately outside
this registry.

## Names and ownership

The accepted concrete names are:

```text
Vxpipe.Providers.Deepgram.STTSocket
Vxpipe.Providers.Deepgram.TTSSocket
Vxpipe.Providers.Telnyx.TelephonyMediaSocket
Vxpipe.Providers.Twilio.TelephonyMediaSocket
```

The socket names describe provider wire implementations. Public speech consumers continue to use
semantic STT/TTS sessions, and telephony consumers continue to use the provider-neutral telephony
contracts. Generic room, turn, policy, permission, readiness, media and persistence modules remain
outside provider namespaces.

## Adding or changing a provider

1. Put the provider root, credential schema and optional pure credential-test request builder in
   `apps/vxpipe_providers/lib/vxpipe/providers/<provider>/`. Add the root to the fixed registry.
   Declare only installed capabilities; an absent entry is the unsupported result.
2. Put concrete speech sessions and sockets in CallEngine or telephony adapters, profiles, HTTP
   handlers and media sockets in Gateway, under the same `Vxpipe.Providers.<Provider>` namespace.
   Follow the [speech provider contract](speech-provider-contract.md) for STT/TTS semantics. The
   manifest names the public session or profile, not every private helper.
3. Use `Registry.resolve_capability/2` at consumers. Keep configuration validation and readiness in
   their owning runtime; a supported manifest entry alone does not imply a usable call. Do not add
   another provider-name dispatch table or a fallback module.
4. Add provider contract tests for exact capabilities, credential shape, request description and
   unsupported cases. Run affected Calls/Console/CallEngine/Gateway suites and the umbrella gates.
   Keep real network interoperability in the tagged integration lane.

## Rejected alternatives

- **One provider OTP application per provider now:** current speech and telephony implementations
  directly implement stable CallEngine/Gateway contracts. Extracting every dependency would broaden
  this namespace change into a runtime redesign; reversing dependencies would create cycles.
- **Dynamic provider registration:** it adds startup ordering and partial-registration states without
  a current requirement for runtime-installed providers. A fixed registry is deterministic and
  compile-time reviewable.
- **One optional-callback behaviour for every capability:** it hides distinct STT, TTS, telephony and
  credential contracts behind a large interface. The provider manifest composes the existing focused
  behaviours instead.
- **Generic fallback adapters:** absence is explicit. No capability lookup retries another provider,
  legacy module or generic wire implementation.

## Implications

Adding a provider requires one manifest and only the capability modules it implements. Backend
catalog consumers can distinguish unsupported capabilities without maintaining their own provider
lists. Provider-private helpers remain private. This migration changes module identity and catalog
lookup but must not change call topology, supervision, retry, cancellation, media or persistence
behavior.

The migration proceeds one provider at a time. The registry declares a provider only when its
schema, credential probe, concrete capabilities and consumers have moved together and passed their
focused tests. The final checkpoint removes any remaining duplicate provider lists and runs the
full umbrella acceptance gates.
