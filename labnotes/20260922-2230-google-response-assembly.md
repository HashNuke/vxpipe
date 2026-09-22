# Google response assembly

Baseline `b355c1d3`: the shared exact-start owner, accepted input origins and
capability response queue are committed; the four root static gates pass. The
real Google controller file remains deliberately red in five first/continued
response cases (49 tests, five failures). All five currently fail at premature
legacy caller-end admission, because their test helper still allocates the
non-opted descriptor. No hosted calls.

Read the milestone response-owner work, Google response-ownership design,
`STSResponses`, `STSSession`, `STSOutput`, `STSInput`, `STSResumption`, and the
real-controller test diff. Added explicit opt-in test correction, actual owner
adoption, exact credit/discard, and model/resumption lifecycle subtasks before
implementation. The local opt-in profile must remain unadvertised until its
controller and broader gates pass; legacy fixture behavior remains separate.

Corrected only the five opt-in controller allocations to `response_start?: true`.
The focused file first failed in five cases at the absent PCM-start grant,
confirming the intended red boundary. Added `STSResponseDelivery` to adapt the
already-tested bounded `STSResponses` owner to exact channel starts, grants,
credits, settlement and discard. Bound the opt-in owner to accepted input
context; retained the legacy path. The five cases turned green. A new focused
renewal test failed because model idle ignored outstanding response playback;
the owner-wide idle check in `STSResumption` fixed it. Text-only and held
pending-response controller cases also pass.

Independent review flagged two hypotheses. A focused controller test proved
post-credit PCM stalled until another boundary (one failure); draining when
new audio is appended made it green. Another focused test proved standalone
provider interruption with no legacy caller turn merged the next reply into
the old response (one failure). Exact response interruption now emits the
matching channel event, discards/ends that response, and lets the next response
get a new identity. A separate focused red proved `interrupt(old_A)` sent a
wire interrupt during newer B generation; exact-owner callback routing fixes
it. The reviewer also flagged the 815-line session against the 800-line Credo
limit. Moved input command normalization/publication into `STSInput`; the
session is now 794 lines. The complete controller file passes 55 tests.

The wider eight-file STS group initially failed one room host-tool test. Its
fake capability had no supervised invocation registry, reproducible in the
focused room test (`:unavailable`). Updated that acceptance test to use the
real supervised capability and completion lease; focused test then passed.
The eight-file group now passes 207 tests, zero failures, no hosted calls.
Root static gates, independent re-review, full umbrella tests and milestone
acceptance remain pending.
