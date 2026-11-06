# Review MCP transport

- Reviewing the transport enabler after browser (`9b8d859a`) and renewal
  (`c229f8eb`) commits. Scope: private Calls projection, guarded MCP provider,
  ClientOptions, pinned ExMCP HTTP/SSE patch, setup/CI and focused tests. Runtime
  catalog/compiler and production UI remain separate.
- Independent source review identified a pre-existing captured Last-Event-ID bug
  in the patched path. A tagged loopback regression seeded an HTTP cursor, observed
  two newer SSE events, then reproduced reconnect sending the old captured cursor.
  SSE now removes the captured cursor when a current stream cursor exists.
- Source review also identified expected credential-rejection exits as potential
  OTP reporting paths. Live SSE reporting reproduced both synthetic bearer and
  custom-header markers in captured reports. Actual supervised runtime startup
  did not reproduce a leak, so that path remains unchanged.
- A live stateless HTTP client exposed a second confirmed path: credential
  rejection exited the synchronous request and reported a custom-header marker.
  The HTTP provider-bearing submission now catches only the fixed rejection atom
  and returns a transport error before network work. SSE keeps terminal rejection
  and redacts OTP status; converting it into an ordinary connection error would
  enter the library's connection retry loop.
- Both dependency files remain pinned by revision, original/patched source hashes
  and patch hash. Regenerated the manifest and compiled the revised dependency in
  dev and test. The seventeen focused transport/privacy/options tests pass, including
  three tagged HTTP cases. The additional wrong-revision and mixed-state patch
  regressions pass; all five patch tests and thirty-three setup tests pass.
- Design review: this enabler depends only on the committed private resolver and
  fixed client profile. Rejected disabling streaming, broad vendoring and an HTTP
  wrapper that would conflict with ExMCP's concrete transport assumptions. It does
  not claim active cross-node revocation or the later runtime source cutover.
- The full tagged MCP suite initially failed before protocol checks because npm
  invoked with `--prefix` from this checkout rejected the official fixture locks.
  Fresh pinned clones installed successfully when npm ran inside their own working
  directories. Both fixture scripts now isolate install/build/start in subshells;
  pinned revisions, lockfiles and protocol scenarios are unchanged. The full MCP
  integration lane then passed: 176 tests, zero failures.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed. The default MCP suite passed 166 tests (10 excluded); the focused
  Calls projection test passed. The last full umbrella pass belongs to the browser
  flow checkpoint (4,875 tests); final milestone-wide gates remain pending.
- Independent exact-index adversarial review found no blocker in the 22-file
  transport checkpoint. Follow-up adversarial review of the full 24-file index,
  including fixture preparation and verification evidence, found no issues.
