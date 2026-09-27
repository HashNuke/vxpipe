# STT readiness test race

The final umbrella rerun of the GPT-Live publication barrier hit the known
`SpeechToTextTest` preparation race recorded in the completion plan. After the
test delivered a fake `Connected` message, it sampled the transport, provider
(misnamed `channel` in the test), and capability with `:sys.get_state/1`. The
provider forwarded that message through the actual speech channel, which could
still be processing it when the capability was sampled. The input binding was
then still `:preparing` under concurrent load.

An initial attempt to wait for the capability's connected signal failed in a
focused run: a prepared session is private, so it does not emit that public
signal. The test now acknowledges the actual transport → provider → channel →
capability message path with `:sys.get_state/1` at each process. The assertions
that the prepared activity origin stays private and the adopted one becomes
visible are unchanged. No runtime behavior changed. The corrected focused
case passed (one test, zero failures) while Gateway was under umbrella load.
The final umbrella rerun passed 2,868 tests, zero failures, 61 tagged
exclusions. Format, warnings-as-errors compile, strict Credo,
unused-dependency and Lean checks passed.
