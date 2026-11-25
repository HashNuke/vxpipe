# Give the handset caller time to interrupt

During the coordinated trial, the operator heard a clipped greeting on the first call. On the second call they said “transfer test” twice and waited for the acknowledgment. The runner recognized the trigger, then timed out waiting for the next question before the recognizer fault was injected. Greeting audibility remains a separate open observation.

The handset-only fixture now asks the agent to read a fixed acknowledgment with a spoken “You can interrupt me now” cue and several sentences of follow-through. The runner prints when it has detected the trigger, and the operator procedure uses the early audible cue. The fixture test failed on the old prompt (seed 370107) and passed with the new prompt (seed 890265). The fixture check establishes the published prompt; handset listening establishes whether it is delivered.

The coordinated Telnyx run (seed 35471) passed the repeat-completed and single correlated answer assertions. The carrier confirmed the bridge and the destination room admitted the call. The runner timed out waiting for the destination transcript of “bridge test,” so this attempt did not establish bridged speech or the subsequent managed-cleanup assertions. Both numbers were restored to QA.

The caller reported hearing “We have lost the audio connection,” then the destination greeting, then “Bravo” after saying “bridge test.” The destination is configured to reply “Bravo” to any caller speech. The report and the bridge confirmation establish that the call reached the destination. The specific transcript and managed-cleanup gates remain open. The beginning of the packaged transfer WAV matches the callback WAV sample for sample for at least 1.3 seconds. The recovery path uses the transfer WAV before dialing, so the shared wording can be heard on a successful fallback transfer.

The five umbrella checks passed, including the default suite with seed 415588. Console reported 681 tests and zero failures. The coordinated handset lane remains separate from the default suite.
