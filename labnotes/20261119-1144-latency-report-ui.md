# Latency report UI

Added framework-neutral report/turn/loader types and revision-preserving page merge,
plus a shared collapsed diagnostic panel in CallConsole's Metrics view when a host
supplies its optional loader. Requests start only when expanded, stop/abort on close,
and refresh serially every5seconds only for live calls. A10second timeout exposes
retry; failed refreshes label retained evidence as previously loaded. Session/denied
responses clear prior evidence. Each view retains only one run page and one turn
page, separate from conversation state.

The Storybook-first preview uses synthetic complete/partial turns. Rows expose
nullable STT/dispatch/text/audio stages in rounded integer ms, with technical
landmarks, clock/source/revision, uncertainty and missing-stage reasons on disclosure.
Whole-call percentile samples remain separately grouped; profile disclosure makes
configuration differences inspectable. This is not pure compute or remote-hearing
latency. Core/UI support is not yet connected to a production HTTP loader.

Initial core/UI tests failed for absent modules. Focused tests then passed. Added
and reproduced access-revocation and empty-later-run-page defects before fixing:
revocation clears prior results; later empty pages retain first-page navigation and
do not claim that nothing was collected. Astra xhigh reproduced empty successor
wording plus observation selection/cursor issues. Four retained paging probes
cover earlier insertion, selected-run disappearance, and fallback stability. All
review findings were reproduced before correction; final independent review is clean.

Rendered Chrome checks covered desktop and390px standalone/shared admin preview,
collapsed/expanded section and row disclosure. Horizontal table scrolling stays
inside the panel (document width390, panel width390, table content541); turn labels
no longer wrap. Keyboard Enter toggles the focused row and retains focus. Screenshots
are temporary verification artifacts, not committed product assets.

Storybook's old process had stopped. Its Tailscale forwarding caused the port check
to reject6007; briefly removed that forwarding, started the existing bin/storybook
in a persistent tmux session, then restored the same6007→loopback6007 forwarding.
Preview remains available over the user's Tailscale network. No provider call or
production deployment was performed.

Remaining D work includes real HTTP decoding/loader composition in both authorized
hosts, transcript references, additional unsupported/denied/large fixtures and final
end-to-end acceptance. No combined D checklist is newly complete.

Final focused core/latency/paging/metrics selection passes21/0; existing shared
CallConsole regression selection passes25/0. Workspace builds and both workspace
and Console TypeScript checks pass. Full-suite verification remains deferred to
milestone completion as instructed.
