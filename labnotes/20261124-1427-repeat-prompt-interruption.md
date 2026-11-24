# Repeat prompt interruption

The existing configured caller test submitted its repeat after playout completed. A second configured test now delivers speech during the repeat phase, observes the speaking phase before completing the question, and verifies the model receives the fresh wording exactly once with neither the abandoned wording nor the cue text in its input. The configured voice receives the expected answer for synthesis. This uses a local media socket and synthetic recognizer.

A room test checks the cue-stop message on the accepted replacement onset, ignores an onset from the old generation and delivers a late playout failure and expired timer while the caller speaks. The fresh final records one completion even when delivered twice. The four room tests and four consecutive runs of the final configured phone test passed. This exercises existing behavior and does not establish handset audibility.
