# Publication worker monitor synchronization

The complete umbrella rerun with seed 774698 failed the existing Calls case
`changed late facts produce another immutable source revision`. It received the
published notification and a monitored `:DOWN` with `:noproc`; the worker could
complete before the test attached its monitor. The source confirms normal
publication immediately stops the short-lived worker. No production publication
behavior is changed.

Use the existing artifact writer's explicit wait/release fixture. Wait for the
first write to start, attach the worker monitor while its writer is held, then
release a valid object receipt. Retain both the exact published notification and
normal termination assertion before publishing the changed source revision. This
preserves the lifecycle assertion instead of accepting multiple exit reasons.

The failing root run provides the red evidence. The focused file passes all three
tests with the original seed 774698. Formatting,
compilation with warnings as errors, strict Credo and the unused-dependency check
pass. Astra reviewed the actual diff and found no bypassed production path or
weakened assertion. The corrected full same-seed root run is now active; its
result remains a required milestone gate.
