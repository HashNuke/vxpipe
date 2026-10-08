# Runnable LLM model catalog

Agent Runtime owns `ModelCatalog.models/1`: it combines the bundled LLMDB snapshot
with the runtime's explicit model overrides. It exposes the six providers supported
by `ProviderSelection`, using public provider IDs (including `fireworks`, whose
native adapter ID is `fireworks_ai`). Provider availability remains the registry's
responsibility at the Call Engine boundary.

The listing keeps text-output, tool-calling models, excludes image/video-output
models, and checks each candidate through the same selection translation used to
start a call. This proves local adapter compatibility; it does not claim that a
remote account has access to every model. The listing requires no provider
credentials and performs no inference or remote model discovery. LLMDB uses the
packaged snapshot in the project's configuration.

Descriptors expose `id`, `name`, `default`, `context_limit`, `tool_support`, and
`voices: nil`. Exactly one recommendation per provider preserves onboarding's
existing choice. Context limits remain null when unknown. `ModelOverrides` owns
the DeepSeek Flash and GPT-6 Luna declarations for both runtime selection and
listing, retaining existing wire protocol and token-limit settings.

## Alternatives and load cost

Duplicating override metadata in the editor would let authoring and runtime drift.
Offering the full snapshot without filtering would advertise image-only models
and configurations the runtime rejects. Live discovery would introduce network
and credential requirements into an otherwise local authoring operation.

No additional persistent-term cache is used. After `LLMDB.load/0`, OpenRouter
returned 260 models: the first listing took 100.3 ms, and ten subsequent listings
took 64.9–89.0 ms while the umbrella tests were also running. The serialized result
was 36,125 bytes; observed process-heap growth during each listing was roughly
142–230 KB (temporary allocations, not retained catalog size). This is acceptable
for an operator request and avoids a second cache with snapshot invalidation
requirements. These measurements describe local execution, not a capacity claim.

## Verification

The catalog tests check all six providers' recommendations, unique IDs, translation
of every listed model, runtime overrides, exclusion of non-chat models, and
rejection of unsupported provider IDs. Existing selection tests continue to cover
wire options and model overrides. The implementation labnote records red/green
and umbrella verification evidence.
