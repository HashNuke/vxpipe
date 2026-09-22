# STS sidecar integration

- Reviewed exact native Astra commit `afd721c1`; independent Astra xhigh source
  review found no scoped issue. Integrated as `4d786b0a` after the preceding
  Google configuration umbrella completed successfully at `9ffe2ab4`.
- The only merge conflict was adjacent milestone bookkeeping: preserved the
  completed recognition-usage task and its main-branch evidence, while adding
  the sidecar configuration subtasks and leaving PCM handling unchecked.
- Focused integrated startup/selection, room transcript modes and Google STT/STS
  codec/session group: **95 tests, zero failures**, seed 0, two schedulers. This
  is the exact compatibility command in the implementation labnotes. An expected
  sanitized capability shutdown log does not indicate a test failure.
- Normative provider contract now states the separate private recognizer field,
  existing STT registry/credential path and room PrivateInit handoff. No new
  runtime changes were made beyond the reviewed implementation commit.
- Format compatibility/conversion, generated-audio recognition and full per-reply
  settlement remain open. No hosted requests or Google STS enablement occurred.
- Post-commit static/full umbrella results will be recorded separately; the
  preceding 2,299-test root pass must not be attributed to this later checkpoint.
