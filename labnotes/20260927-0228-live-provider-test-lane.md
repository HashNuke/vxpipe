# Live provider test lane

The user asked for a group of credentialed third-party tests that ordinary
`mix test` never runs, and clarified that runtime credentials come from tenant
services with platform fallback. This pass inventoried 21 integration files.
They include local HTTP/database/loopback checks as well as real OpenAI,
Deepgram, Gemini, Zenmux, Twilio, Telnyx, and S3 calls, so the existing
`:integration` tag alone is too broad to name a billable run. The live tests
use inconsistent extra tags; several read keys directly from environment
variables. Current default test helpers exclude `:integration` in the apps
that own live tests. Calls and Providers currently start ExUnit without that
exclusion, so future live tests there need the helper updated first.

The current service contract in `docs/platform-and-tenant-services.md` and
`ScopedProviderCredentialsTest` is tenant presence first, platform if absent,
and fail closed on an unusable tenant credential. The engine's
`CredentialSource` accepts a platform-owned resolved credential only through
the host-injected source. A live adapter protocol test can keep a secret
environment input; an end-to-end configured-service test must use the normal
source and a dedicated test tenant. Mixing those two claims was rejected.

Local `mix help test` confirms `--only`, `--include`, and `--exclude`. The
installed Mix version rejected `--dry-run` even though a newer online manual
documents it; do not use that flag in this repository's command examples.
With the previous harness guard and `OPENAI_API_KEY` unset,
`mix test --only hosted test/integration/gpt_live_hosted_test.exs` from the
CallEngine child selected two tests and skipped both, zero failures. No live
connection was opened.

The decision and staged migration are in `docs/live-provider-tests.md`. Added
valued `live_provider` tags to the 11 current real-service integration modules.
All eleven modules now use `VXPIPE_LIVE=1` as their only run gate; the user
chose this shorter name after the first draft used a long run flag, then asked
to remove the remaining provider-specific run flags. Provider credentials and
fixture settings remain separate inputs. With the flag disabled,
`mix test --only live_provider` selected and skipped every test in
AgentRuntime (4), Artifacts (1), CallEngine (4), and Gateway (5), with zero
failures and no provider calls. The configured-service fixture and authorized
live runs remain to implement. The umbrella root command naming the four
owning integration directories selected the same 14 skipped tests in 3.8
seconds. An OpenAI-only Mix filter selected its two skipped tests. With
`VXPIPE_LIVE=1` and `OPENAI_API_KEY` explicitly unset, those two tests failed
at `System.fetch_env!/1` before a network connection, proving the single run
gate activates them.

Verification after renaming the guard: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`, and
`mix deps.unlock --check-unused` passed from the umbrella root. The first
root `mix test` run reported a timeout assertion in the unrelated
`TTSCancellationTest` under full-suite load; that test passed immediately
when rerun from CallEngine (1 test, 0 failures). A second full-suite run
reached a green CallEngine result (1,677 tests, zero failures) before being
stopped because the user changed the live-test flag contract during the run.
The final root `mix test` run after the separate source-cutover fix passed
2,868 tests with zero failures. Formatting, warnings-as-errors compilation,
strict Credo, and the unused-dependency check also passed against the final
files. No live provider was called; the missing-key check failed before a
connection. Progress was sent through `pushnotify` during the checkpoint.
