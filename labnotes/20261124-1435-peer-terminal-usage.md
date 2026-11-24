# Peer terminal usage

The linked-leg owner previously waited for all carrier command workers to drain before starting final usage storage. An abnormal end-command observer exit permanently left drainage unconfirmed, even when the carrier later reported the linked leg had ended.

A regression bridges a managed peer, holds its end command, kills the command observer and dispatches the linked-leg hangup. Before the change, storage never received that terminal observation. The owner now submits the immutable final usage batch as soon as it receives terminal evidence. Acknowledging cleanup still requires confirmed command drainage and durable usage. The test verifies the successful peer observation and its carrier event ID, waits for storage acknowledgement, and checks that cleanup membership is pending. The carrier cleanup module passed all 13 tests and the regression passed 21 consecutive executions.

The preceding umbrella run loaded the previous Calls module before the timing change and then read the newly edited persistence test. Its only failure was the old module rejecting a timed announcement. The fresh umbrella run started after the timing and linked-leg fixes.
