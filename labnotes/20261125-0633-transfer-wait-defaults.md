# Restore transfer wait defaults

The shared live telephony Call Spec builder explicitly published a null wait_sounds field on every generated spec. The handset reception and destination inherited that override. The Call Engine already resolves omission or an empty object to destination-specific defaults, and resolves null at either the individual slot or whole-object level to silence.

A regression assertion on the published reception and destination source failed before the change (seed 215410). Removing the shared override makes both use omission. The Console telephony fixture suite passed nine tests (seed 850212).

All six compiler contract cases passed (seed 437958). The unattended Telnyx recovery lane passed with the corrected shared fixture (seed 651393, 31 seconds), restored both QA numbers and retained its local room recordings. This live lane exercises carrier fallback. It does not establish handset audibility during the ordinary agent transfer.

The umbrella run passed its nine non-Console applications. Console exposed eight fixture constructors with nil options from the previous local recording change. Defaulting the fixture's options to an empty list preserved their existing non-recording behavior. One preexisting source assertion explicitly required the silent override; its expectation now verifies omission. All eight portable fixture tests passed together (seed 787216).

The complete Console rerun passed all 683 tests. Formatting, warnings-as-errors compilation, strict Credo, unused dependency and diff checks passed.
