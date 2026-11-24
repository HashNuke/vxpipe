# Transfer usage gate

The handset runner previously stopped at the original leg’s carrier-ended journal entry. It now waits for the original call and leg to end, the managed cleanup acknowledgement to persist, and one terminal telephony observation for each of the original and linked attempts. It resolves the linked attempt from the durable transfer intent. The observations must identify distinct carrier legs and delivery IDs in the original session.

The focused offline evidence check initially failed to compile because the predicate was missing. The completed predicate accepts both answered and unanswered cases and rejects missing, duplicate, misattributed and wrong-outcome evidence. The offline Console fixture module passed seven tests. Handset audio, database evidence on a real transfer and carrier cleanup in the live lane still require a coordinated call.
