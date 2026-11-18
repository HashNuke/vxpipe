# ReqLLM wire patches

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

The live acceptance investigation also exposed inconsistent Google usage
provenance. Buffered decoding retained token counters but lost whether output was
reported; streamed normalization could mark synthesized zero counters as reported.
The patch carries reporting facts from raw `usageMetadata` through both paths.
Explicit nonnegative candidate counts (including explicit zero), with absent or
valid reasoning counts, permit the runtime's bounded correction policy; inferred,
missing or malformed output counts do not. Reasoning tokens still consume the cap.
`google_usage_repair_test.exs` exercises native and portable encoding in both modes,
including known, zero, reasoning, missing, inferred and malformed counts.
The ordered-Part source-state upgrade is also checksum-verified by the installer.
For streams, reporting facts come from the last model/usage event rather than
ReqLLM's generic OR merge. A final absent or malformed count revokes correction;
an intermediate missing count followed by complete final usage remains eligible.
The private per-event marker does not change the shared counter merge behavior.

The cumulative patch also retains Fireworks `reasoning_content` in outgoing
assistant messages. ReqLLM 1.29.0 strips it even though Fireworks documents its
use for interleaved thinking. Other rejected fields remain stripped. The direct
DeepSeek/Fireworks wire regression demonstrates the lost field and its restoration
in buffered and streamed tool continuations. See the
[transport investigation](../../docs/design/universal-replies-chat-replay.md).
The historical patch filenames remain stable; the manifest now covers Fireworks
as well as Google and upgrades all four previously prepared source states.

Router continuation extends the same manifest to generic chat decoding/building,
OpenRouter and Zenmux. Exact raw reasoning maps survive both modes, explicit
reported-model provenance survives streaming, and malformed private fields remain
invalid instead of disappearing. Raw Zenmux details are now re-encoded. The modern
runtime-owned `vxpipe_native_tool_calls_only` option disables SDK parsing of tool
syntax quoted in private reasoning; the default retains legacy behavior. No flag
is sent in provider JSON. All five preceding prepared source states upgrade to
the same final hashes. See `router_replay_wire_test.exs` and
`router_native_call_test.exs` for real HTTP regressions.

Buffered Chat Completions responses retain normalized `usage_reported` and
`billing_usage_complete` facts, matching streaming validation without replacing
provider-specific usage fields. This permits bounded correction with explicitly
reported output (including zero), while missing or malformed usage remains
ineligible. Public Session HTTP regressions cover all four compatible transports.
