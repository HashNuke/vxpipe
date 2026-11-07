# Verify the hosted directory catalog

Completion audit found a literal missing acceptance artifact: T1 requires a tagged
read-only live catalog check, but the only directory integration test covers an
HTTP loopback transport. Repository search found no live directory tag/test. This
is an acceptance automation gap, not a reproduced runtime bug.

Fresh anonymous versioned GETs against the public origin return HTTP 200 with one
category and three MCP entries, no native providers. Railway whoami remains
Unauthorized and no Railway connector tool is available. The earlier access and
workflow questions remain unanswered. Add an opt-in check through Console's actual
client, without provider credentials, and retain a failing public release gate
until the compatible publisher and definitions have been deployed.

The actual public run fails at the intended native-adapter assertion (one test,
one failure), after Client validates the tenant, category and platform responses.
The first lane-isolation command also selected the test: ExUnit includes override
other excluded tags when the test carries both integration and the live tag.
Removed the generic tag. The corrected --include integration run excludes the
only test (zero executed, zero failures, one excluded; seed 860870). The test
helper comment and usage docs explicitly prohibit adding the generic tag. This
is a reproduced test-lane configuration error, not an application runtime defect;
no test of ExUnit's dependency-owned precedence was added.

To validate the complete acceptance case, copied the preserved 16-entry catalog
through SQLite's backup API into a separate temporary database, rebuilt the actual
publisher at a5ed7a5, and served it through the existing loopback TLS proxy with a
trusted local CA. This preserved import contains the 13 native entries corrected
at definitions commit 40d763a. The first proxy invocation used relative certificate
paths and failed before listening; using absolute paths fixed that fixture setup.
The exact live test then passes all assertions (one test, zero failures, seed
579842). It uses real Go HTTP responses, normal certificate/hostname verification
and Console Client/Page validation, not a substitute JSON fixture. Asset URL
metadata is checked by the schema; this does not establish hosted logo delivery.

Documentation now provides the opt-in command and separates local/staging checks
from hosted release evidence. The full default umbrella verification is rerunning
with the added test excluded. Hosted deployment remains blocked on Railway access;
workflow approval is still unanswered.

The final documented command against the public origin still fails only for missing
native adapters (seed 7183). Astra reviewed the final source, actual local green,
public failure and corrected tag-isolation evidence, and approves closing the
automation task without closing public release. No further code correction is
requested. The original source-only tag-isolation assumption was explicitly
withdrawn after the parent reproduced ExUnit's include behavior.

Prepared Railway CLI sign-in under the already-authorized release request and
relayed the activation link immediately in chat and pushnotify. The owned process
remained live for its full polling window, then exited with Device code expired
without authorization. No deployment was attempted. Both account/project token
environment variables are absent, and a service-context status query also returns
Unauthorized, ruling out a valid project-token-only session hidden by whoami.
No activation codes, tokens or environment contents are retained in this record.

Final serial verification exits zero: format, warnings-as-errors compilation,
strict Credo, default umbrella tests and unused-dependency checks all pass. The
umbrella executes 5,000 tests with zero failures and 265 exclusions (seed 774698);
the new live check accounts for the extra exclusion. Frontend source is unchanged
since its green 1,065-test/TypeScript/ESLint run. No source-cutover or speech state
machine changed, so Lean does not apply. The hosted-check fixture was stopped
after verification. Public deployment and explicit workflow approval remain open.
