# Async diagnostic inference

- Continuing after c56a13e0 with a clean checkout. Before automatic worker
  attachment, standalone inference needs non-suspending admission: the existing
  ActivityRuntime.submit call can wait five seconds on a blocked runtime.
- Three focused tests failed for the absent diagnostic admission API. Added an
  opt-in handle on explicitly configured runtime instances, with atomic admission
  before copying/sending. Normal operational runtimes have no such handle.
- Capacity is fixed per runtime incarnation, including queued and running work.
  Audio is at most 32,000 bytes and serialized stream state at most 16,384 bytes;
  capacities range 1–32. Busy inference rejects immediately rather than building
  another runtime queue. Native task termination, not result delivery, releases
  the reservation. Runtime replacement cannot revive an old handle.
- Checks capture authority before offering, at runtime admission, before model
  load/classification, and before result delivery. A 250 ms per-active-job check
  retires revoked diagnostic jobs; existing runtime native-task slots stay held
  until DOWN. The ordinary synchronous API and its result protocol are preserved.
- Initial affected tests passed 11/0; additional boundedness/revocation tests and
  independent review follow. This does not yet compose the isolated runtime into
  production or attach source workers; those C tasks remain unchecked.

- Retained a red tensor-view regression: a valid 256-byte Nx context retained a
  2 MB backing binary. Submission now recursively detaches BEAM binary views in
  the bounded stream while preserving pinned-model native tensor references.
  Small malformed pending/tensor/sample state is rejected before reservation.
  A real packaged-model test passes two successive offers with native recurrent
  state, so this is not verified only against mock classifiers.
- A producer killed between reservation and delivery can strand capacity. The
  conservative permit stays occupied until runtime restart, like the existing
  Calls writer admission gate; no timeout guesses that unknown work is absent.
  This can make diagnostics unavailable, but bounds retained/unknown admissions.
  Serialized byte limits cover BEAM data, not opaque native allocations; tensor
  dimensions and native memory remain responsibilities of the pinned Silero model.

- Final affected suite:95 tests/0 failures. Format, warnings-as-errors compile,
  strict Credo, unused-lock check and Lean verification pass. Astra xhigh re-review
  clean:18 focused tests plus5 independent lifecycle checks, including revocation
  during loading, actual periodic cancellation, owner death, busy correlation and
  stale runtime handles. Full umbrella suite is still running; no final milestone
  completion or deployment is claimed.
