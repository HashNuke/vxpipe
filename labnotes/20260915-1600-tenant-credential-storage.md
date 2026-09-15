# Tenant credential storage — preparatory cleanup

## Worktree audit and user steering

- The active milestone was a specification with no tenant-credential implementation. The initial
  dirty worktree contained earlier TOML work and unrelated website/visual edits.
- The user asked to start by discarding misaligned prior changes, then deleted the untracked
  `apps/vxpipe_config`, runtime TOML proposal/sample and provider pages while this audit ran.
  The user also committed the milestone itself as `9ad11c4`; no existing commit was undone.
- Restored only reviewed tracked TOML/configuration/auth source, tests, child manifests, lockfile,
  launcher, environment example and related documentation to the committed baseline. These were
  uncommitted changes; restoring them produces no source deletion diff to commit.
- Removed orphaned TOML provider-page tests/development page and the homepage link to the deleted
  catalog. Did not overwrite unrelated website/design/labnote changes; the user separately
  committed or removed these while cleanup ran. The user subsequently removed the untracked
  central ReqLLM version/link map too; checkpoint 5 must recreate that provider-doc facility.
- The baseline still has global provider env/profile behavior. It will be replaced in the owning
  vertical slices; this cleanup does not claim the tenant flow or final cutover is implemented.
- The direct TOML app/dependencies are gone. `toml` remains transitively required by ReqLLM's
  `llm_db`; deleting its lock entry would break dependency hygiene without removing a runtime
  configuration path. The milestone now distinguishes this from the discarded platform loader.
- Updated final cutover to explicitly require `env.sample`, mandatory placeholders, concise
  comments and commented optional settings. No new environment variables were introduced here.

## Independent review

GPT 6 Astra xhigh (`cleanup_review`) independently examined the current diffs and confirmed the
coherent discard scope. It found no reason to retain the new auth implementation wholesale:
OAuth/Vertex file paths and simultaneous Bedrock API-key/IAM inputs contradict the milestone.
Retain the following design evidence for checkpoint 5's new red tests, in their proper owners:

- Explicit tenant credential-source selection and no generic key reuse.
- Vertex ambient access-token suppression with explicit service-account data.
- Recursive rejection of auth/HTTP overrides in definition options.
- Nested provider-option preservation and mutually exclusive authentication shapes.

The review covers cleanup only. Each implementation slice and final acceptance still need review.

## Verification

- Source scan: no `Vxpipe.ConfigFile`, `vxpipe_config` or `VXPIPE_CONFIG` reader/dependency remains
  in apps, root runtime configuration, launcher, Procfile or environment example.
- `git diff --check` passed after cleanup.
- Formatting, warnings-as-errors compilation, strict Credo and unused-dependency checks passed.
- Launcher process tests passed. Astro production build passed (4 pages).
- The docs test suite passes 3/4: its existing homepage test still requires the Elixir/OTP badge
  removed in committed `d41abe1`. Confirmed the same mismatch in HEAD; this is unrelated to the
  discarded provider link and is left outside this milestone's commit.
- Rendered headless Chrome inspection at 1440×1000 and 390×844 confirmed Quickstart has its
  documentation link and no orphan provider link; no horizontal overflow at the narrow width.
  Screenshots are in ignored `tmp/tenant-cleanup-{desktop,quickstart,mobile}.png`.
  The existing Astro preview was used after its live CLI status confirmed port 4333; the
  attempted separate preview exited without starting a new server. Closed only our browser.
- Checked 131 relative file links in the milestone/index: none missing.
- Full root `mix test --preload-modules --max-requires 1 --seed 235296 --max-cases 4` completed:
  1,436 tests, one failure, 16 integration exclusions. Gateway's existing
  `human handoff handles release_speech_loss preparation` timed out waiting two seconds for a
  terminal transfer server-message. All other application suites passed. Runtime/test source
  equals HEAD after cleanup; no causal link to discarded work is established.
- Failure evidence is retained in ignored `tmp/tenant-cleanup-tests.log`. The exact named case
  passed in an isolated Gateway run with the same seed/preloading/concurrency and no source
  changes. Command from `apps/vxpipe_gateway`: `mix test
  test/vxpipe/gateway/http/human_transfer_webrtc_test.exs --only 'test:test human handoff handles
  release_speech_loss preparation' --preload-modules --max-requires 1 --seed 235296 --max-cases 4`.
  Output is in ignored `tmp/tenant-cleanup-isolated.log`. This is an unresolved intermittent
  baseline failure, not evidence of a full-suite pass or a fixed cause.
- Both cleanup reviews found no blocking issues; the follow-up confirmed removal of active
  references and advised changing provider-doc tasks from preservation to recreation after the
  user's deletion. This was incorporated. Final milestone implementation/gates remain open.

## Next checkpoint work

Implement checkpoint 1 as a complete Google/Deepgram tenant voice flow, using small commits inside
that slice. Start with focused red provisioning/storage/workflow tests, then the inline schema,
credential gates/resolution and ordinary prepare/join integration. Keep the full vertical exit
unchecked until it works. Baseline test failures stay visible for later umbrella acceptance.
