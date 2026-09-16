# Align timeline times

## Decisions

- Message headers use the full available timeline width while message text remains limited to a readable line length.
- Trailing message content reads as streaming state, metrics action and time. When call metrics are enabled but a turn has no measurements yet, the metrics action remains visible and disabled.
- Tool rows use the same left-border rhythm as activity events with a tinted background. Their trailing content reads as disclosure action, status and time.
- `CallSnapshot.metricsEnabled` distinguishes unavailable turn measurements from a call where metrics are not enabled.

## Metric follow-up

- Known capability groups are LLM, input guardrail, output guardrail, TTS and STT; any subset may be present.
- Known measurements include response duration, TTFT, TPOT, TPS, RTF and audio-to-first-audio.
- Turn presentation needs both whole-turn measurements and capability-grouped measurements without inventing absent capabilities or values.

## Verification

- Red: the focused test failed because metric-enabled turns without measurements had no reserved metrics action.
- Green: 10 focused console tests and `npm run check` pass.
- Browser inspection passed for the human-handoff timeline at 1440×1000 and 390×844 in dark mode. Message, event and tool times share the same right edge in both viewports.
