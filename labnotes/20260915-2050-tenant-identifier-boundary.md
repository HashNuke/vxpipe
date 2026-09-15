# Tenant identifier boundary

The tenant-opening database acceptance exposed an existing protocol mismatch: the control plane
creates 16-character unpadded URL-safe Base64 tenant keys, including possible initial `_` or `-`.
CallInvocation accepts them, but seven Engine command constructors require an alphanumeric first
character and prevent those persisted calls from starting. The failure appeared in the additional
tenant's cache-isolation scenario (seed 527483). Replace its random tenant key with a controlled
leading-underscore key so that the integration failure is deterministic.

Keep this correction separate from opening playback/privacy. Preserve tenant identities already
stored or issued. Narrow the expanded alphabet to tenant IDs; retain the existing command, room,
participant and section identifier rules and the Engine's 1–128 character tenant bound. Do not
change the control-plane key format, add prefixes, or rewrite existing tenant rows.

Added owning Engine constructor regressions before implementation for both allowed leading
characters, invalid tenant inputs, and unchanged room identifier rejection. This is a project
protocol boundary test, not a test of Base64 or random-number generation.

The deterministic command run failed **14 tests, 7 failures**, seed 580320: each constructor
rejected the valid leading character. Each now selects the full URL-safe alphabet for `tenant_id`
only, retaining its existing error protocol and bounds. Focused green: **14 tests, 0 failures**,
seed 123337. The persisted two-tenant opening scenario also passes with a deliberately leading-
underscore tenant key (**4 tests, 0 failures**, seed 369604), including actual room and connection
startup. Its opening/privacy assertions belong to the next checkpoint.

Verify this standalone correction in a detached checkout containing only its seven constructors,
focused test, control-plane documentation and this note. Keep opening changes out of that commit.

The standalone identifier checkout passed formatting, warnings-as-errors compilation and strict
Credo. Its umbrella completed **1,503 tests, 1 failure, 30 excluded** (seed 235296, concurrency
four). All 413 Gateway cases passed. The sole failure was the existing live-only STT policy test
not receiving its first audio frame after readiness. That case also failed in isolation. A
temporary state diagnostic observed an open/demanded ingress and passed, which does not prove
a runtime fix; it was removed. The test now explicitly asserts the public room input-admission
state before sending audio, preserving its audio assertion and timeout. The focused case passes
with that stronger precondition. Treat the earlier timing observation as unresolved, and validate
the complete affected file and combined checkpoint before committing.

## Standalone commit verification

The detached checkout containing exactly the identifier change passes all **14 focused command
checks**, formatting, warnings-as-errors compilation, strict Credo and unused-lock verification.
The earlier standalone umbrella result above remains red; do not report it as a passing umbrella
run. The combined opening/identifier closeout passed all **43 focused opening/speech-policy
tests** and static gates, then exposed a different existing partial-handoff `speech_loss`
progress failure. It remains under investigation. Commit this independently verified constructor
correction now, and keep final umbrella acceptance and the broader milestone open.
