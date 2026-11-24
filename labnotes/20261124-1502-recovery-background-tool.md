# Recovery during a background tool

The configured phone fixture originally had no non-blocking host tool. Added an opt-in tool for the test call spec. The model dispatches the existing waiting test tool, the caller opens a new question, and recognition is replaced while the invocation is still running. The model request for the fresh repeated question contains the same pending invocation. Releasing the original worker delivers its successful ToolCallCompleted event to the caller connection. Only one worker starts.

The initial case failed before tool admission. An intermediate assertion waited for another model request after the tool finished, which also depends on voice output delivery. The final check observes the tool completion itself. The configured case passed three consecutive runs. The carrier-exit matrix also injects the same cue failure twice. All four failure paths passed with one callback recording and a terminal carrier event.

This adds test coverage. The answered transfer, caller hangup during a real linked dial, and human observations remain in the live gates.
