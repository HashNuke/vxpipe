# Handoff progress recipient

## Finding

While verifying the inline-credential checkpoint, the umbrella's native
`after_speech_adoption` case timed out waiting for the destination's preparation update.
The isolated case passed, but source review found a deterministic recipient bug:
connection promotion clears `transfer_attempt_id` before the complete handoff releases.
Progress selected the destination only through that marker, so delivery depended on whether
the promotion notification reached RoomAuthority before the new progress event.

The pending attempt already pins `destination_connection_id`. Continue selecting that exact
connection along with the initiating connection and any still-private attempt connection.
Unrelated connections must not receive the update. No audio timing or deadline changes belong
to this fix; the other native audio failures remain separate, unresolved observations.

## Red-green evidence

- Wrote the focused recipient test before changing production code. It failed exactly on the
  promoted destination's absent message: **1 test, 1 failure**, seed 336715. The initiator
  received its update.
- The recipient fix passed **1 test, 0 failures**, seed 131831. An initial formatting command
  used umbrella-relative paths from the child directory; reran it with child-relative paths.
- Extracted only this production patch, its test and labnote against committed parent `e14e82d`
  in a disposable checkout with separate build/dependency copies. The focused test passed
  **1/0**, seed 796663; root formatting, warnings-as-errors compilation, strict Credo and
  unused-dependency checks passed. Reviewed the exact patch before committing it separately.
- Combined umbrella verification is running with the inline-credential work still staged.
  The earlier native adoption case passed in isolation before this fix (**1/0, 67 excluded**,
  seed 235296); the focused red test establishes the recipient defect without relying on that race.
