# Synchronize editor save verification

- During Morse API frontend verification, the full Console asset suite passed
  757/758 tests but failed the existing browser-unload-guard case: the saved
  message was visible while the previous `beforeunload` listener still ran.
- The listener is installed and removed by an effect keyed to `guarded`. A
  rendered saved message is not an acknowledgement that this effect's cleanup
  has completed. The test now uses bounded `waitFor` around the externally
  observable guard behavior, then still checks that historical viewing has no
  guard. No runtime code, deadline, or assertion outcome changed.
- The original full-suite failure is the red evidence. After the change the
  complete owning test file passes all 28 tests. A full frontend rerun follows
  with the Morse API changes; its evidence belongs to that checkpoint.
