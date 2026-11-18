# ReqLLM Google wire patch

ReqLLM 1.29.0's Google buffered chat decoder converts a `functionCall` into the
common tool shape without attaching its `thoughtSignature`. Its object decoder
already calls the correct attachment helper. Consequently a normal Session tool
continuation sent ReqLLM's dummy signature instead of the upstream opaque value.

`google-native-signatures.patch` reuses that existing helper in the buffered chat
path. It changes neither the output schema nor tool dispatch. The manifest pins
original and patched source hashes and the patch hash. `bin/patch-req-llm` refuses
unknown source states and verifies repeat application. No dependency-directory
edit is the delivered artifact.

`bin/setup` and CI apply the patch before compiling ReqLLM. Release preparation
must do the same for the production environment, as documented in
[scripts/qa/README.md](../../scripts/qa/README.md).

Evidence: the real-adapter Google Session tool conversation in
`dialogue_repair_wire_test.exs` failed because its second encoded request contained
the dummy signature. It now retains the original signature and native result,
with all authorized tools still declared. The patch preparation test exercises
fresh application, repeatability and preservation of unknown local edits.

Remove this patch only after upgrading to a dependency version that passes this
wire regression without it; update the pinned source evidence at that time.

The Google native object wire regression also proves two SDK mismatches:
`prepare_request(:object)` raised an explicit 100-token cap to 200, and streaming
JSON synthesized a `structured_output` call absent from the provider response.
The patch preserves explicit caps and disables that synthesis for Google, whose
stream response builder already extracts objects from raw text. Actual native
calls (including a real tool named `structured_output`) remain untouched. Raw
fenced/duplicate JSON remains available to the runtime's shared strict decoder.

The manifest includes an exact-state upgrade from the preceding signature-only
patch. Fresh installs and already prepared checkouts converge on the same hashes.

The buffered object decoder also concatenated `thought: true` text into public
JSON. Its text filter now excludes thinking parts, matching streaming behavior.
The native wire test reproduces private thinking followed by valid dialogue and
asserts only the original dialogue reaches the runtime text boundary.

Google continuation regressions extend the patch to retain private reasoning
in buffered object JSON responses and native function call/result IDs in encoded
history. The runtime owns strict replay binding and bounds; the dependency patch
only preserves existing provider protocol fields. The manifest supports both
previous committed patch states, each tested against the same final hashes.

Signatures are not limited to thinking chunks. The patch captures ordered raw
Google Parts in typed private SDK records, including public and empty signed
Parts, and prevents the Google streaming builder from overwriting them. Runtime
replay stores canonical text/call references instead of duplicate public data.
Outbound reconstructed Parts preserve order and attributes; native ID provenance
controls whether calls/results carry IDs, leaving originally ID-less calls intact.
The permanent Google replay wire/bounds tests cover these contracts in both modes.
