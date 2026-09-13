# Readiness worker cancellation

- The recording-output checkpoint's broader engine run exposed a failure in the existing room
  preparation expiry contract: the enclosing request finished, but its blocked connection query
  remained running. Re-running that exact test reproduced the failure.
- A focused direct connection cancellation check failed for the same reason. A separate room
  cancellation check also failed with the root stream still unlinked, even after the nested
  connection stream was corrected. Both checks monitor the actual blocked worker and confirm
  that its media connection remains usable after cancellation.
- Inspected the installed Elixir task-stream implementation: parent-down cleanup propagates to
  linked query tasks. Selected supervised linked streams for the engine's room and connection
  preparation operations, retaining the existing bounds and safe adapter exception handling.
  Rejected increasing assertion timeouts: request ownership, not a longer wait, was missing.
- The first focused correction run passed 31 connection/inventory checks. The final run includes
  direct room cancellation and the recording-output checks: 69 engine checks and 26 Gateway
  checks pass. All five root gates pass in the combined worktree: formatting,
  warnings-as-errors compilation, strict Credo, 1,166 tests with zero failures and 15 integrations
  excluded, and unused dependencies.
- Recording-output changes are being verified in the same worktree but will be committed as a
  separate coherent checkpoint. This change does not alter live capability/codec ownership.
