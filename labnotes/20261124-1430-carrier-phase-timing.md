# Carrier phase timing

The leg journal previously retained the expiry and persistence timestamp. A delayed or retried write could obscure the interval between carrier commands and callbacks. The original owner now captures elapsed milliseconds when it first observes a phase and queues the observation unchanged for persistence. The existing call details projection includes this optional field. Ownerless reconciliation and legacy observations keep their original representation.

The journal test initially failed on the missing clock origin and the persistence test rejected the timed entry. After implementation the journal test exercised each phase with an ambiguous first write and an exact retry. All eleven telephony store tests passed, including a timed announcement, legacy hangup, and a duplicate announcement with a different deadline.

A second journal test queued terminal evidence behind an unacknowledged hangup write, then redelivered the terminal event with a later timestamp. Storage received the first terminal offset on both attempts. Both journal tests, 40 configured caller recovery cases, formatting, compilation, strict Credo, unused dependencies and the Lean verification lane passed.
