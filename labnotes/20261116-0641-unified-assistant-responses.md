# Unified assistant responses

## User clarification

- User identified the mismatch between ordinary message content and the bare
  interruption result. After an optional format question, user explicitly chose
  `interrupt_agent: false|true` in the common response and `agent_mode` on messages
  sent to the agent. They requested all user/assistant variations to review.
- Inspected current Message, ModelResponse, native submission results and async
  completion normalization. This remains specification work, not implementation.

## Proposed catalog and ownership

- Extended the existing separate design with variables and examples for participant
  input in both modes, platform events, terminal application results, all four
  common assistant dialogue outcomes, native exchanges, settled assistant history
  and derived summaries. Native records remain their original protocol shape.
- Common model-authored dialogue content now uses `type: participant_message`,
  nullable `text` and `interrupt_agent`; the earlier bare response_text contract is
  superseded. Runtime supplies role, participant identity and delivery evidence.
- Every new application user envelope includes the receiving agent's mode at its
  initial input admission. Freeze it through retries/replay and preserve per-agent
  attribution; do not refresh old mode values or invent legacy modes. Actual
  acoustic overlap remains independent evidence. Native wire tool blocks are
  preserved, even where a provider uses the user role for those blocks.
- Kept output schema identical across normal/greeting/idle/tool-continuation/
  overlap dialogue. Partial-input null-text and ordinary no-interruption rules
  are operation admission constraints, not separate response envelopes.
- Updated classifier/TTS contracts, delivery review and existing owning A/C tasks.
  Added one mode-lifecycle task to message A to avoid a circular dependency on
  voice C. Voice C consumes that state for cue/overlap policy. Checkpoint counts
  stay three and six; task counts are now 23 message and 72 voice tasks.
  The prior extraction review did not cover this amendment; a fresh review is
  recorded below.

## Verification

- Independent Astra xhigh review identified a P2 omission: explicit zero/unknown
  playback representations were missing from the catalog. Added examples,
  passive-context semantics and message A acceptance, distinguishing empty
  known-zero evidence, unknown null evidence and valid model silence. Clarified
  basic mode lifecycle ownership. Re-review found no material findings.
- Documentation checks passed across 20 changed Markdown files: 265 local links,
  50 heading anchors and 13 parsed JSON blocks. Eight application user examples
  carry a valid frozen mode; six common model replies share the exact fields.
  Zero/unknown delivery examples preserve empty/null distinctions.
- Verified all 23 message tasks (A8/B7/C8) and 72 voice tasks
  (A11/B4/C17/D12/E17/F11) remain unchecked. Index has 65 entries, 50 complete
  and 15 pending, with message format preceding voice. Historical completed
  Scribe checkpoint remains unchanged. `git diff --check` passed.
- Documentation only. No code, provider calls, runtime/browser acceptance or
  commits; no model artifacts added.
