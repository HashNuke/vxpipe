# Test memory investigation

## Scope

Investigate the host `mix test` process killed during the earlier focus-refresh
verification before implementing the personal-settings milestone. Work belongs
on `qa`; the user requested focused tests only and no environment-file reads.

## Findings

- The host has 7.6 GiB usable RAM and no swap. The live `vxpipe` container is
  limited to 1 GiB; the killed test BEAM ran directly on the host, outside that
  limit. Kernel evidence recorded approximately 2 GiB anonymous RSS for it.
- Removed an abandoned 1.9 GiB build scratch directory from tmpfs after archiving
  its source/Git state on disk. Available memory rose by approximately 2 GiB.
  That reduced host pressure but did not explain the test VM's own allocation.
- A temporary, ignored sampler recorded Linux RSS/high-water marks, Erlang
  memory categories, allocator carriers, process counts and largest-process
  function names. It did not inspect application payloads or credentials.
- The audio-output files near the original failure passed 52 focused cases at
  roughly 293 MiB RSS. Four Silero cases passed at roughly 513 MiB RSS. These
  were not the source of the multi-GiB peak.
- Repeating the 29-case call-spec file three times retained 51 room trees.
  `TestCallStartup.start_call/2` did not register teardown for rooms started
  under the application supervisor. This is test isolation/resource ownership;
  production rooms correctly outlive the process requesting their creation.
- Two focused files reproduced approximately 1.8 GiB RSS before Gateway tests
  even ran. The compiler's SSA optimizer occupied approximately 1 GiB in one
  process (`beam_ssa_share`, `beam_ssa`, `ordsets`). The WebRTC file generated
  twenty copies of a roughly 600-line scenario, eleven preparation cases and
  ten recovery cases with similarly duplicated bodies. Stopped this diagnostic
  run once the cause was established, before another OOM.
- Engine's eager module preload, native media libraries and allocator carrier
  reservations contribute to the baseline. They do not explain the large
  compiler-process heap. RSS and `:erlang.memory/0` are different measurements;
  do not describe all RSS as retained application objects.

## Changes and verification

- Move the three largest generated test bodies into shared scenario functions.
  Preserve the individual test names, tags, parameters and assertions. This is
  a mechanical test refactor; no runtime or production compiler options change.
- Add a teardown regression before fixing the test startup helper. Capture the
  exact room incarnation so cleanup cannot terminate a later room with the same ID.
- After the scenario extraction, the same focused pair passed: 29 Engine cases
  and 67 enabled Gateway cases (one integration case excluded). High-water RSS
  was 1,039 MiB, versus 1,837 MiB in the stopped baseline, a 43% reduction even
  though the baseline had not finished compiling. Gateway took 248.7 seconds;
  total sampled run took 261.2 seconds. The moved scenario bodies were compared
  after normalizing indentation/explicit parameters and remained identical.
- Red: the first room test's on-exit assertion found a retained incarnation.
  The initial line selector pointed above the first test and selected nothing;
  corrected it before implementing cleanup. Green: the complete 29-case file
  passed three consecutive runs, leaving **zero room trees and 448 processes**,
  versus 51 trees and 1,720 processes before. Peak RSS was 869 MiB; final RSS was
  635 MiB. Native libraries/code/allocator reservations remain resident, so
  process/resource cleanup does not imply RSS should immediately return to zero.
- No production behavior or dependency changed. The focused tests retain the
  existing assertions and native media paths; no test cases were dropped.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency
  checks passed. No full suite was run, following the user's explicit scope.

## Decisions

Do not raise the production container limit, disable compiler optimizations,
change production room ownership, add swap, or run another full suite to hide or
reproduce this issue. Keep builds/tests sequential on this shared host. The
initial sampler used a relative path that broke when umbrella Mix changed cwd;
fixed it to an absolute path and used the subsequent runs for detailed samples.

References: [Erlang memory accounting](https://www.erlang.org/doc/apps/erts/erlang.html#memory/0)
and [allocator carriers](https://www.erlang.org/doc/apps/erts/erts_alloc.html).
