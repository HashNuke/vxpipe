# Agent output retirement

2026-09-22/23 UTC. Branch `sts-impl` started clean at `2a25665e`.

- Inspected the still-open output-retirement task. `RoomAuthority.SpeechToSpeech`
  kept active private-to-public associations only; terminal handling removed
  the entry, so a repeated start could mint another public turn. Added explicit
  reproduction and ordered-envelope subtasks to the milestone before code.
- Focused red: `mix test test/vxpipe/call_engine/room_authority/sts_output_identity_test.exs:91`
  failed because the state gained a new `sts_turns` entry and `next_sequence`
  advanced after completion. A first accidental location filter at line 88 ran
  the preceding test; the corrected line 91 produced the expected red.
- Accepted fix: retain acknowledged channel event sequence through legacy and
  opted-in queue entries, active output and room owner messages. Room terminal
  retirement advances one scalar watermark, and late text/terminal events
  require the exact active sequence. Capability replacement clears the bound
  watermark with the association map. This avoids finite tombstone eviction.
- The expanded affected capability/controller/room group passed 203 tests, zero
  failures; the embedded room/lifecycle group passed 27/0. Expanded room checks
  cover 25 sequential retired starts, stale text/terminal isolation when a
  private ref is reused, a later live association and capability replacement.
  Queued legacy and opted-in response tests assert that the original accepted
  event sequence survives the busy slot and matches later start/completion.
- Independent read-only Astra xhigh review of the diff found no concrete defect;
  the reviewer independently ran the 202-test affected group (202/0).
- The first call-engine child `mix test` run completed 1,412 tests, one failure,
  30 integration exclusions. The failure was a 100 ms Morse ready assertion in
  `morse_sts_conversation_test.exs` under suite load. Isolated rerun: 1/0. No
  code fix or claim of a green full run yet; rerun the child gate before final
  acceptance. Expected failure-path GenServer logs were noisy but not failures.
- Design/contract decision recorded in `docs/sts-agent-output-retirement.md`
  and `docs/speech-provider-contract.md`. This does not prove upstream provider
  deduplication, Google cross-origin cutover, or hosted behavior.
