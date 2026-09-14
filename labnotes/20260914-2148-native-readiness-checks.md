# Native readiness checks

- Continue the approved native WebRTC direction; no UI changes or development-server restart.
- The existing AI handoff case already withheld TTS readiness. Extend it to block the destination
  model constructor first, verify caller wait audio and held text, then release only the model
  and retain the independent TTS barrier before the cue and greeting.
- Reuse TestSelectiveAgentRuntimeModelProvider's existing blocked and blocked-unavailable modes.
  Add a native failed-model-preparation recovery variant alongside destination/phase/player/TTS
  loss. It must retain the caller output and room media, cue before release, speak through the
  original source voice, and accept another caller turn.
- These are acceptance checks of the implemented shared handoff, not a new runtime behavior or
  testing framework. Keep independent remote-tool readiness evidence explicitly open.
- Bounded recovery investigation is recorded separately in the transfer-recovery-race labnote.
  Improve native audio failure context before interpreting the intermittent Morse timeout.
- Focused native model checks: two tests, zero failures (18 excluded), ordinary deadlines and
  no trace flag. Waiting is established before blocked model initialization; failed initialization
  recovers without replacing source media. No runtime change was required for either contract.
- Full native transfer file: 20 tests, zero failures, seed 931998, ordinary deadlines. The same
  seed previously failed during the bounded mixed repetition; a passing run does not close the
  intermittent audio or recovery concerns.
- Checklist review: split verified model/TTS acceptance from remaining tool/configuration/privacy
  evidence. No checkpoint prerequisite or runtime contract changed.
- User requested ongoing progress through `pushnotify`; CLI help confirmed its message interface.
  First progress notification was sent successfully. Continue notifications for material progress
  and blockers in addition to normal conversation updates.
- All five root gates passed after the acceptance additions: format, warnings-as-errors compile,
  strict Credo, umbrella tests, unused-lock check. Umbrella: 1,304 tests, zero failures, 15 exclusions,
  seed 547223, max_cases 4. Gateway: 336 checks, including 20 native transfer cases.
- Logs use the temporary `vxpipe-native-readiness-gates-` prefix and results JSON. Focused logs:
  `vxpipe-native-model-readiness.log` and `vxpipe-native-readiness-full.log`.
- Another agent committed the docs-site visual during this work (`56adb3e`); preserve that commit
  and its remaining untracked visual labnote. No files in vxpipe-docs are part of this checkpoint.
