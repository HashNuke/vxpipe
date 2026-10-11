# macOS native VAD

## Scope

- User rejected skipping native VAD tests and asked to make VAD work on macOS.
  Removed all conditional skip changes, their support module, and the CI toggle.
  Stopped the in-progress umbrella test run before rebuilding native code.
- Preserve the optional runtime `vad` contract and all existing inference tests.

## Evidence and investigation

- Native inference reproduced six failures in 18 focused tests before the skip
  experiment. The additional Google barge-in and WebRTC VAD-enabled tests also
  require real inference; none should be excluded for this fix.
- Host: Apple Silicon, macOS 27.0, Xcode 27.0, Rust 1.94.1.
- Ortex's Mach-O `LC_SYMTAB.stroff` is 14,087,356 (four bytes off an eight-byte
  boundary), matching the loader's `mis-aligned LINKEDIT string pool` error.
- [Rust issue 157750](https://github.com/rust-lang/rust/issues/157750) describes
  the same failure with stripped macOS dynamic libraries. Investigating an
  Ortex-scoped Cargo profile override to preserve symbols during compilation.
- The interrupted umbrella run also reported a non-native stale-frame failure
  in the hybrid queued-old-STT-onset room test. Check independently after native
  loading is fixed; do not hide it behind a VAD condition.

## Fix and verification

- Rebuilding only Ortex with `CARGO_PROFILE_RELEASE_STRIP=none` made its string
  table offset 14,123,120 (eight-byte aligned). No dependency upgrade, native
  artifact patching, or operating-system changes were needed.
- The real Silero, model-cache, Scribe acoustic session, and spoken barge-in
  suites passed: 22 tests, 0 failures, no skips. The earlier native failures
  provide the red baseline; this build-configuration change needs no new test
  duplicating existing inference assertions.
- Added the Cargo setting to macOS-only Ortex/Rustler configuration. It applies
  to every Mix environment, preserves release optimization, and leaves Linux
  configuration unchanged. Documented rebuilding existing cached artifacts.
- Prefer a scoped compiler setting over globally replacing the user's Rust
  toolchain or modifying dependency sources. Consider removing the workaround
  when the project's supported Rust toolchains all contain the upstream fix.
- Rebuilt Ortex with the repository configuration and no shell override;
  compilation succeeded. Native WebRTC with `vad: false` and `vad: true` passed:
  2 tests, 0 failures (2 unrelated tests excluded by the name filter).
- Both queued-old-STT-onset room cases passed independently: 2 tests, 0 failures
  (35 unrelated tests excluded by the name filter). No room-state code changed.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused
  dependency checks passed. The full umbrella suite passed: 3,564 tests,
  0 failures, with 128 existing integration/live exclusions. No native VAD
  tests were skipped. The earlier stale-frame failure did not recur.
- User confirmed both macOS and Linux must keep working. The build override is
  conditional on Darwin; Linux and its existing CI coverage are unchanged.
  Docker did not provide a usable Linux runtime on this host, so no fresh Linux
  inference execution is claimed.
- User requested a commit; the checkpoint contains only the build configuration,
  local development documentation, and this labnote. No runtime speech state
  machine changed; the Lean lane is not required for this configuration fix.
