# WebRTC hold audio after an observer disconnects

The umbrella run at seed 652242 lost the 250 Hz hold tone on the observer’s surviving connection immediately after its first connection closed. The surviving peer had received RTP before the disconnect. Running the unchanged case in isolation normally passed, including with two schedulers.

The regression holds the transfer worker at policy validation after it reads the room inventory. It closes the original data channel, observes its connection exit and releases validation before the existing deadline. With this order, the original code returned `:resource_unavailable` during transfer preparation and the surviving peer stopped receiving the tone. This reproduces the observed symptom without a prior test. The original suite failure recorded the missing tone but did not record the internal failure reason.

The worker now reconciles the room inventory when the readiness collector reports failure. A changed graph is probed on the same attempt and deadline. A failure against the same graph still ends preparation. The native test continues through wait playback, reconnection and transfer. No test or production media deadlines were extended.

The controlled reproduction failed once before the fix. After the fix the full native scenario passed five consecutive executions (one initial run plus four repeats). Formatting, warnings-as-errors compilation, strict Credo and unused-dependency checks passed.
