# Verify reconnected call-spec references

Close the T6b composition evidence gap using the existing real PostgreSQL and MCP
wire fixture. Publish once, disconnect through the authorized Calls boundary,
confirm secret resolution/preparation/runtime failure, explicitly reconnect with
submitted credentials, retain the exact published revision and original route,
prepare at generation 3 while generation 1 stays fenced, and execute the same tool.
This adds an acceptance test for existing behavior; no runtime behavior changes.

Initial fixture mistakes were a missing authority-refresh callback and comparing
whole compiled tool bindings despite deliberately changed credential generations
and rediscovered schema metadata. Corrected the fixture callback and compare stable
ID/name plus explicitly changed generations. The unchanged published revision still
uses exact equality. All five saved-runtime cases pass. The wire fixture does not
implement session DELETE, so the probe logs a nonfatal cleanup HTTP 500; this does
not establish successful remote session deletion.

Astra independently reviewed the test and passing log and approved closure of the
specific call-spec composition gap. Scope is bearer authentication, fixture user
identity, real durable stores, public Calls/Gateway composition and actual MCP wire
execution. Prior rendered and OAuth evidence remains separate. Root gates pending.
