# STS ten-call measurement

## Baseline and quiet-window coordination

Measured main revision `5792d797bf0439a81dbb8dfc4f960376cdb3659c`, after parent
review/integration of the Gateway wait-ownership/adoption/owner-receipt checkpoint
and load harness plus timing/timer follow-up. The Gateway milestone merge kept
both the previous 2,243-test root failure evidence and the new controlled repairs;
the private policy revision 8-to-10 gap remains explicitly open. Integrated root
format, warnings-as-errors compile, strict Credo and unused-lock checks pass.

Gateway agent confirmed all native/child test handles terminal. Google-config
agent's initial dependency compile was still live, so measurement waited for that
same handle to finish (exit 2, 16 tests/five expected configuration reds). It
confirmed no compile/test process remained. Parent static gates also finished.
Only then started `bin/sts-call-load measured`, at approximately 16:55 UTC.
Background development services remained running; no claim of an otherwise
idle host is made. The measured command exited 0 after 25.3 seconds, three tests,
zero failures. Did not restart or terminate a live command to obtain a window.

## Results and limitations

All three modes ran ten concurrent pinned room calls. Per mode: 29 completed
turns, ten interruptions, nine healthy survivors after one room fault, ten
cleaned calls, 2,106 accepted input frames, no rejected/dropped input, no
rejected/cleared sink chunks and no errors. All recorded latency distributions
have samples; missing values were not converted into zeros. Retained all p50/
p95/p99 values with sample counts, drop/cleanup and sampled memory/mailbox
observations in [the load methodology/results](../docs/development/sts-comparative-call-load.md).
The raw report remains temporary log `vxpipe-sts-load-measured.log`.

Host facts captured before the run: four x86-64 AMD EPYC-Genoa CPUs, 7,750 MiB
RAM, OTP 28, Elixir 1.19.5. The script uses two ordinary schedulers, one dirty
CPU/I/O scheduler each and two async threads. Original runtime, phase, memory,
queue and PCM bounds were unchanged. This is paced embedded PCM, not hosted,
native transport or physical hearing evidence; no warmup or production-tail
claim. Recheck after remaining material runtime changes in final acceptance.

## Continued work

Released the quiet window explicitly after command completion. Boyle resumes
private Google prompt/tool-schema wiring from its confirmed red tests. Carver
continues the separately recorded private policy-gap repair with expanded
private-media/STT ownership scope, preserving strict public snapshot validation,
real policy intervals and original handoff deadlines. Parent retains STS
output retirement/shared invocation work and the serial root gate. No milestone
completion, Google advertisement, hosted call or remote push is implied.
