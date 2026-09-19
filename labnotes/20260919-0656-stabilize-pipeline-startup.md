# Stabilize pipeline startup

- Scoped-provider checkpoint validation reproduced failures in the existing real
  WebRTC and Telnyx output pipeline tests while waiting for initial readiness.
  Their two-second startup limit is not the behavior these tests exercise: they
  verify authorization, frame format/order and paced output after readiness.
- Kept the readiness acknowledgement and all frame/protocol assertions. Gave
  native fixture initialization its own ten-second limit; subsequent frame and
  acknowledgement limits remain two seconds. No production timeout changed.
- Red evidence: umbrella seed 772211, concurrency four, failed initial readiness
  in both files. Stopped that already-failed run before repeating validation.
- This verification correction is a separate reviewed checkpoint from scoped
  provider inheritance, as requested by the user.
- Focused evidence: both output files and the earlier ingress-policy file pass
  together, 17 tests with seed 772211. The next full umbrella run passed both
  readiness tests but failed a separate Twilio source-recovery speech assertion:
  1,733 tests, one failure, 40 exclusions. This commit does not claim that the
  umbrella suite is green; source-recovery investigation remains open.
- Reviewed the three readiness assertion changes before committing: no frame
  checks, production deadlines, or expected acknowledgements were removed.
