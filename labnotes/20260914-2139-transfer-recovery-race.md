# Transfer recovery race

- Previous goal turn made progress: committed caller RTVI progress (`5b87209`) and native Morse
  speech integration/PCM conversion (`bc42ef5`). Revalidated HEAD and worktree; only the other
  agent's docs-site/visual labnotes were dirty before this task.
- Full 19-case and first umbrella runs intermittently failed phase-loss recovery with unavailable
  before the 750 ms budget. Focused and traced runs passed; final 1,303-test root run passed.
  The cause was left explicitly open. Investigate with the native client, preserving the existing
  deadlines and healthy service instances.
- Read `mix help test` and use a bounded name-filtered repeat-until-failure run to reproduce in
  one VM. Temporary error-only stage probes identify where recovery stops; remove before commit.
- The normal (non-traced) focused phase-loss run passed 31 executions with error-only stage probes
  (initial execution plus 30 repeats).
  A five-repeat full-file run passed two complete 19-case iterations, then stopped on the Morse
  case's audio timeout during the third. No recovery-stage probe fired. This does not establish
  that the recovery race is fixed, nor does it implicate Morse in the earlier recovery failure.
- Removed every temporary runtime probe. Keep the recovery concern open instead of changing
  production deadlines or retrying unspecified failures without a reproduction.
- Added frequency/connection context to native tone failures; the previous generic timeout did
  not identify whether the missing signal was a connection cue or conversational Morse audio.
- Morse-only `--repeat-until-failure 10` finished with eleven successful executions (the initial
  execution plus ten repeats). No production or timing adjustment was made to obtain those passes.
  The mixed-run audio timeout remains intermittent; failure context now identifies its frequency.
