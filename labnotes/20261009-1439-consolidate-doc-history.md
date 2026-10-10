# Consolidate milestone plans and historical docs

Date: 2026-10-09 UTC
Status: complete — relocation, consolidation and focused verification passed.

## Scope and decisions

The user approved the 12 milestone consolidations and 35 historical archives from the [curation review](20261009-1138-docs-curation-review.md). The 69 user/developer documentation refinements remain deferred. Their existing files receive only incoming-link repairs and necessary Docker-availability wording. No implementation, provider execution, release or commit is part of this checkpoint.

- Preserved all 47 source bodies and headings in separate destination files. Historical archives use first-add Git author timestamps normalized to UTC, explicitly identified as source-commit provenance rather than investigation start time. Filenames have two-to-four-word task slugs. Existing task notes are linked, never overwritten.
- Long plans/designs are unnumbered companions under `labnotes/milestones/`; eight existing owners incorporate scope/contract summaries and point to those companions. The milestone index lists companions separately, with no new implementation-order entries.
- Existing owner/index completion flags and review holds are preserved. Companion checklists retain their original evidence status; this migration supplies no new acceptance results.
- Archive/companion banners separate historical status from maintained contracts and scope authority. Key conflicts include proposed agent D1–D3, STS tool D4 versus old continuation wording, later Google selection, GPT-Live hosted/reseed observations, retired Console routes, and accepted scoped services versus earlier prototypes.
- Reference links, reference-style definitions and HTML href/src references are rebased. Historical fenced examples are preserved. Evidence assets remain at their existing paths. User-facing contract extraction/rewrites will be considered with the 69 refinements; the full source evidence remains accessible meanwhile.
- `bin/setup` completed earlier in this same checkout during the curation review. This documentation-only checkpoint uses proportionate content/link verification rather than rerunning runtime/provider suites.

## Parallel consolidation design review

Three read-only reviewers examined source/owner contracts and dependency order before consolidation: speech completion/acceptance; Console/onboarding; historical provenance plus credential/Docker scope. Their actionable findings were incorporated into owner summaries and companion banners. Specific fixes preserve the distinction between accepted services and incomplete bootstrap/first-use gates, distinguish pending variable/metric designs from supported APIs, and keep packaging held. Design review is recorded separately in each changed owner milestone.

## Actual path map

Historical sources are preserved as linked supplements rather than appended into existing notes; this keeps their original fragment identities and avoids collisions between repeated headings. Milestone companions preserve detailed plans while their owners control active checklists. Former paths below are migration provenance, not active links.

| Former source | Destination | Disposition |
| --- | --- | --- |
| `docs/call-spec-gap-review.md` | [20260906-1452-call-spec-gap-review.md](20260906-1452-call-spec-gap-review.md) | Historical archive |
| `docs/credential-reader-boundaries.md` | [20260915-1521-credential-reader-boundaries.md](20260915-1521-credential-reader-boundaries.md) | Historical archive |
| `docs/deepgram-finite-input-proof.md` | [20260922-2032-deepgram-finite-input-proof.md](20260922-2032-deepgram-finite-input-proof.md) | Historical archive |
| `docs/deterministic-text-turn.md` | [20260903-1851-deterministic-text-turn.md](20260903-1851-deterministic-text-turn.md) | Historical archive |
| `docs/elevenlabs-agent-ownership.md` | [20260930-2255-elevenlabs-agent-ownership.md](20260930-2255-elevenlabs-agent-ownership.md) | Historical archive |
| `docs/elevenlabs-turn-ownership.md` | [20260930-1119-elevenlabs-turn-ownership.md](20260930-1119-elevenlabs-turn-ownership.md) | Historical archive |
| `docs/ex_mcp-fixes.md` | [20260910-0059-exmcp-fork-fixes.md](20260910-0059-exmcp-fork-fixes.md) | Historical archive |
| `docs/existing-provider-credentials.md` | [20260915-1655-existing-provider-credentials.md](20260915-1655-existing-provider-credentials.md) | Historical archive |
| `docs/flux-close-stream-probe.md` | [20260922-2102-flux-close-stream-probe.md](20260922-2102-flux-close-stream-probe.md) | Historical archive |
| `docs/google-sts-response-ownership.md` | [20260922-2053-google-sts-response-ownership.md](20260922-2053-google-sts-response-ownership.md) | Historical archive |
| `docs/jido-tool-execution.md` | [20260908-1637-jido-tool-execution.md](20260908-1637-jido-tool-execution.md) | Historical archive |
| `docs/model-inference-turn.md` | [20260904-2202-model-inference-turn.md](20260904-2202-model-inference-turn.md) | Historical archive |
| `docs/model-tool-invocation.md` | [20260905-1125-model-tool-invocation.md](20260905-1125-model-tool-invocation.md) | Historical archive |
| `docs/morse-duplex-scripted-reseed.md` | [20260926-2218-morse-duplex-scripted-reseed.md](20260926-2218-morse-duplex-scripted-reseed.md) | Historical archive |
| `docs/native-deepgram-tts-session.md` | [20260920-1314-native-deepgram-tts-session.md](20260920-1314-native-deepgram-tts-session.md) | Historical archive |
| `docs/native-stt-contract.md` | [20260919-1348-native-stt-contract.md](20260919-1348-native-stt-contract.md) | Historical archive |
| `docs/native-stt-room-integration.md` | [20260920-0827-native-stt-room-integration.md](20260920-0827-native-stt-room-integration.md) | Historical archive |
| `docs/native-tts-cancellation-findings.md` | [20260920-0041-native-tts-cancellation-findings.md](20260920-0041-native-tts-cancellation-findings.md) | Historical archive |
| `docs/native-tts-deadline-findings.md` | [20260920-0041-native-tts-deadline-findings.md](20260920-0041-native-tts-deadline-findings.md) | Historical archive |
| `docs/native-tts-request-admission.md` | [20260920-0041-native-tts-request-admission.md](20260920-0041-native-tts-request-admission.md) | Historical archive |
| `docs/native-tts-usage-playback.md` | [20260920-0403-native-tts-usage-playback.md](20260920-0403-native-tts-usage-playback.md) | Historical archive |
| `docs/rtvi-participant-connection.md` | [20260903-1823-rtvi-participant-connection.md](20260903-1823-rtvi-participant-connection.md) | Historical archive |
| `docs/scoped-speech-experiment.md` | [20260919-1124-scoped-speech-experiment.md](20260919-1124-scoped-speech-experiment.md) | Historical archive |
| `docs/speech-activity-feasibility.md` | [20261001-0059-speech-activity-feasibility.md](20261001-0059-speech-activity-feasibility.md) | Historical archive |
| `docs/speech-adoption-fix.md` | [20260919-1220-speech-adoption-fix.md](20260919-1220-speech-adoption-fix.md) | Historical archive |
| `docs/speech-complexity-audit.md` | [20260920-0041-speech-complexity-audit.md](20260920-0041-speech-complexity-audit.md) | Historical archive |
| `docs/speech-deadlines-and-failure-containment.md` | [20260919-1312-speech-deadline-evidence.md](20260919-1312-speech-deadline-evidence.md) | Historical archive |
| `docs/speech-provider-comparison.md` | [20260919-0858-speech-provider-comparison.md](20260919-0858-speech-provider-comparison.md) | Historical archive |
| `docs/speech-provider-expansion.md` | [20260930-0648-speech-provider-expansion.md](20260930-0648-speech-provider-expansion.md) | Historical archive |
| `docs/speech-startup-isolation.md` | [20260919-1124-speech-startup-isolation.md](20260919-1124-speech-startup-isolation.md) | Historical archive |
| `docs/speech-topology-experiment.md` | [20260920-0041-speech-topology-experiment.md](20260920-0041-speech-topology-experiment.md) | Historical archive |
| `docs/sts-activity-provenance.md` | [20260923-0243-sts-activity-provenance.md](20260923-0243-sts-activity-provenance.md) | Historical archive |
| `docs/sts-external-room-control.md` | [20260923-0131-sts-external-room-control.md](20260923-0131-sts-external-room-control.md) | Historical archive |
| `docs/sts-input-context.md` | [20260922-2102-sts-input-context.md](20260922-2102-sts-input-context.md) | Historical archive |
| `docs/sts-response-start-grant.md` | [20260922-2133-sts-response-start-grant.md](20260922-2133-sts-response-start-grant.md) | Historical archive |
| `docs/agent-sts-completion-plan.md` | [agent-sts-completion-plan.md](milestones/agent-sts-completion-plan.md) | Owned milestone companion |
| `docs/credential-cutover-scope.md` | [credential-cutover-scope.md](milestones/credential-cutover-scope.md) | Owned milestone companion |
| `docs/debug-console-metrics.md` | [debug-console-metrics.md](milestones/debug-console-metrics.md) | Owned milestone companion |
| `docs/developer-console-and-onboarding.md` | [developer-console-and-onboarding.md](milestones/developer-console-and-onboarding.md) | Owned milestone companion |
| `docs/getting-started-docker.md` | [container-quickstart-plan.md](milestones/container-quickstart-plan.md) | Owned milestone companion |
| `docs/gpt-live-completion-plan.md` | [gpt-live-completion-plan.md](milestones/gpt-live-completion-plan.md) | Owned milestone companion |
| `docs/gpt-live-hosted-check.md` | [gpt-live-hosted-check.md](milestones/gpt-live-hosted-check.md) | Owned milestone companion |
| `docs/platform-and-tenant-services.md` | [platform-and-tenant-services.md](milestones/platform-and-tenant-services.md) | Owned milestone companion |
| `docs/provider-expansion-acceptance.md` | [provider-expansion-acceptance.md](milestones/provider-expansion-acceptance.md) | Owned milestone companion |
| `docs/rtvi-call-variable-projection.md` | [rtvi-call-variable-projection.md](milestones/rtvi-call-variable-projection.md) | Owned milestone companion |
| `docs/sts-tool-lifecycle.md` | [sts-tool-lifecycle.md](milestones/sts-tool-lifecycle.md) | Owned milestone companion |
| `docs/tenant-setup-experience.md` | [tenant-setup-experience.md](milestones/tenant-setup-experience.md) | Owned milestone companion |

## Verification

- All 35 historical sources exist at top-level dated archive destinations; all 12 milestone sources exist as owned companions. All 47 former source files are removed from `docs/`; exactly the 69 deferred sources remain there.
- Compared every source body with its pre-migration working copy: only additive framing and documentation-path repairs differ. Original headings/HTML IDs, fenced examples, and canonical outgoing link targets are preserved. Independent review also compared ordered links and external URLs.
- Checked repository Markdown links and fragments against the pre-migration baseline: no new missing file or heading targets. The baseline had 28 missing local-file links and one missing fragment, including historical removed-source evidence; these were not silently repointed to different modern code.
- Compared all original milestone/index Markdown task lists: content, order and completion flags are unchanged. The companion index adds no ordered milestone or acceptance checkbox.
- Verified archive filenames against Git first-add UTC timestamps and two-to-four-word slugs. Destinations did not overwrite existing task notes. Existing notes received only path repairs; curation/current checkpoint notes record the migration separately.
- Follow-up independent speech, Console/onboarding and archive/scope reviews found no blocking findings. Minor grammar and repeated-reseed provenance wording were corrected.
- `git diff --check` and whitespace checks for new/untracked files passed. Unrelated tracked worktree contents and the Git index are unchanged. The two Elixir and one Storybook HTML edits are documentation comments only; no runtime/UI behavior changed.
- No runtime suites, browser checks or paid-provider calls were needed or claimed for this documentation-only change. No commit was created.

## Remaining work

The 69 documentation refinements remain unperformed. During that separate discussion, choose the final guides/reference organization and reconcile current supported behavior against source and milestone acceptance. No historical measurement or proposal was promoted to a runtime guarantee by this migration.
