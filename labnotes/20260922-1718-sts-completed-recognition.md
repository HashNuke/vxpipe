# STS completed recognition

Independent native Astra xhigh review of `4f5d2fb1` found that later idle
recognizer loss overwrites a successful final while playback is still pending.
Recorded and reopened the usage task before adding its controlled regression.
The fixture accepts ONE, emits one acknowledged final after generation completes,
then is killed and replaced before playback completion. Verify retained text and
successful recognition usage, with the accepted 6,300 ms unchanged.

The full root suite is still running against the committed `4f5d2fb1` runtime;
its Call Engine lane already completed (1,122 tests, zero failures, 17 excluded).
Do not recompile or modify runtime beneath that gate. The initial regression can
run in a separate Elixir VM against existing compiled test artifacts, loading
test configuration and the owning test file without invoking Mix or writing build
outputs. Apply/compile the runtime repair only after that root command finishes.

The new permanent regression runs red against those existing artifacts: 23 tests,
one failure, seed 0. Its final recognition usage is `:failed`, expected
`:succeeded`; accepted duration remains 6,300 ms. No runtime was changed during
the root run. Reproduction from root, without invoking Mix:

```sh
ERL_FLAGS='+S 2:2' elixir -e '
Code.prepend_paths(Path.wildcard("_build/test/lib/*/ebin"))
Application.put_all_env(Config.Reader.read!("config/config.exs", env: :test, target: :host))
{:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
ExUnit.start(exclude: [:integration], seed: 0)
Code.require_file("apps/vxpipe_call_engine/test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs")'
```

## Repair and verification

The prior root command completed successfully: all five gates, 2,282 tests,
zero failures, 45 excluded (seed 0). Only then changed runtime. The failure
handler now retains a binary acknowledged final and successful recognition
outcome when generation has already completed. Unfinished recognition, failed
input and explicit finalization-error markers still take the original failure
path. Retirement/restart is unchanged, so later replies await a new ready
recognizer instead of consuming old evidence.

The same six-file capability/room command listed in the preceding usage labnote
passes **119 tests, zero failures**, seed 0, two schedulers. The new regression
checks 6,300 ms, successful usage, retained transcript and no duplicate usage
after old-provider `DOWN` and replacement startup. Independent native Astra
xhigh re-review found the P2 resolved and no new scoped issue. Multi-segment
aggregation and success-boundary turn correlation remain explicitly open.

Commit this focused repair before running its broader checks. The prior full
root result belongs to `4f5d2fb1`, not this subsequent implementation.
