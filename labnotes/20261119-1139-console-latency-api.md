# Console latency API

Added session-only report and run-turn endpoints under the canonical tenant call
API and tenant host alias. Both reuse Calls read authority and the independent
latency repository. Runtime database composition now configures that read port.
Explicit presentation preserves run/profile/clock provenance, revisions, nullable
stages and microsecond precision without serializing arbitrary struct fields.
Paging accepts only bounded limits/cursors. Missing calls/runs share a generic404;
storage errors return503 without internal details. Responses are private/no-store.

Red: endpoint/runtime selection20 tests,9 expected failures for missing routes and
runtime read-port wiring. First green attempt exposed invalid short tenant IDs in
the fixture; corrected to real16-character tenant keys. Subsequent selection20/0.
Independent Astra xhigh source review is clean.

Real local HTTP inspection with agent-browser/Chrome and dummy identity/repository
confirmed anonymous401, login200, report200/schema1, turns200 and private/no-store.
Chrome required --no-sandbox on this host; no production data/provider was used.
The same browser also verified the previous authenticated login redirect reaches
/tenants, resolving that checkpoint's earlier browser-launch verification gap.

This checkpoint exposes the API only. Typed core state, lazy UI loading, revision
merging, live refresh and rendered report acceptance remain open in milestone D.

Expanded focused endpoint/permission/runtime selection passes36/0. Root formatting,
compile warnings-as-errors, strict Credo and unused-lock checks pass. No full-suite
or live-provider run was performed, per the user's current verification scope.
