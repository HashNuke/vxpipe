# Mix-only live tests

The user requested Mix filters as the entire live-test opt-in: `live_providers`
for the group and shorter `live_<provider>` tags for individual providers.
The earlier `VXPIPE_LIVE` gate made an explicitly selected test skip, requiring
two controls for the same decision.

Local `mix help test` and the official Mix/ExUnit filter documentation confirm
`--only`, `--include`, and exclusion precedence. A first OpenAI selection with
`--only live_provider_openai` selected no tests because that tag did not yet
exist. The implementation gives each of the 11 real-service modules both
`:live_providers` and a fixed provider tag, then excludes `:live_providers` in
all nine child test helpers. Fixed atoms avoid any dynamic atom creation.

The live modules no longer carry `:integration`. Because `--include
integration` can include a test even when another tag is excluded, keeping
both tags would allow a broad local-integration command to select billable
tests. The remaining local integration tests keep their existing tag and
default exclusion.

With `OPENAI_API_KEY` explicitly unset, an ordinary test of the GPT-Live file
and one using `--include integration` each excluded its two tests. `--only
live_openai` selected both and failed at the missing-key check before any
connection. Credentials and fixture settings are still inputs to a selected
test; there is no separate run-toggle environment variable. The umbrella
command names the four owning test directories because children without a
matching test produce a no-tests result under `--only`.

`--only live_providers` on the exact OpenAI file also selected both tests and
stopped at the missing-key check. A root command naming representative files
from Gemini, S3, OpenAI, and Twilio selected none by default. Formatting,
warnings-as-errors compilation, strict Credo, and the unused-dependency check
all passed.

The first full root `mix test` run finished with three failures in unchanged
tests: STT input binding observed a nil provider after a transport restart,
WebRTC source cutover returned `:deadline_elapsed` instead of
`:source_unavailable`, and a five-participant WebRTC handoff timed out waiting
for audio. Each failed test passed when rerun by exact file and line. A second
root suite run with `--max-cases 2` reduced scheduler contention and passed
all 2,868 tests with zero failures. The initial default-concurrency failures
remain a test stability risk; no source-cutover or speech state machine code
changed in this checkpoint.

The current selection contract and remaining configured-service fixture work
are recorded in `docs/live-provider-tests.md`. No live provider was called.
