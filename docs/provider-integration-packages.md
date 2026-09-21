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

Capability presence and runtime readiness are different facts:

- **unsupported** — the manifest has no capability entry;
- **supported** — the manifest names an implementation;
- **configured** — the requested scope has locally valid configuration and credential bindings;
- **ready** — the owning runtime completed its existing startup/readiness contract.

Credential testing is optional and does not determine whether another capability may be configured.
Model inference remains the shared ReqLLM integration. Provider manifests do not duplicate ReqLLM;
Google and Zenmux model support continues through the agent-runtime catalog.

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
```

The socket names describe provider wire implementations. Public speech consumers continue to use
semantic STT/TTS sessions, and telephony consumers continue to use the provider-neutral telephony
contracts. Generic room, turn, policy, permission, readiness, media and persistence modules remain
outside provider namespaces.

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
