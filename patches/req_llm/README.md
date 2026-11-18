# ReqLLM native-call signature patch

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
