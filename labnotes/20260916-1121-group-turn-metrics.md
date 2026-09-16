# Group turn metrics

## Decision

- The message tooltip groups measurements by whole turn or by the capability named in a capability-scoped metric.
- Absent capability groups are omitted. The fixture intentionally demonstrates Turn, LLM and TTS without implying that input guardrail, output guardrail or STT is always present.
- The initial metric vocabulary is response duration, TTFT, TPOT, TPS, RTF and audio-to-first-audio. Values retain their reported units.
- The durable console design and milestone now record the same grouping and optionality.

## Verification

- Red: the focused tooltip test failed because Turn, LLM and TTS headings did not exist.
- Green: 10 focused console tests and `npm run check` pass.
- Browser inspection passed at 1440×1000 and 390×844 in dark mode. Floating UI keeps the grouped panel within each viewport.
