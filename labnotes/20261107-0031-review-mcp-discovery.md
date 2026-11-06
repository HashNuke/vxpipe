# Review MCP discovery

- Independent source review identified four foundation gaps: later OAuth module
  dependencies in capability selection; unsanitized failures in spawned discovery
  callbacks; unchecked retained metadata/scopes; and a pinned challenge parser that
  rejects permitted whitespace around parameter separators. Composed cancellation
  and supervisor-restart evidence also remain required.
- A callback regression failed with the synthetic private marker escaping in a
  worker exit. Normalize exceptions, throws and exits inside that worker before
  reporting its result. The default HTTP adapter catches its own failures; this
  reproduces an injected-callback boundary, not a remote-server secret leak.
- Connection-storage checkpoint committed as `219ee0b5`; discovery remains separate.

- Metadata red run failed four focused contracts: malformed retained capabilities,
  invalid challenge/advertised scopes, and permitted parameter whitespace. Pure
  OAuthCapabilities now validates those fields and owns grant/signing predicates;
  later authorization/signing code delegates without becoming a discovery dependency.
- Challenge normalization preserves quoted/escaped content. A follow-up review
  found bare Bearer schemes rejected by cowlib; focused tests failed for bare
  challenge fallback and then permitted empty list elements. The compatibility
  layer recognizes these without inventing params; ambiguous Bearer challenges,
  malformed trailing params and empty challenge lists remain rejected.
- Manual issuer fallback initially failed its regression. It now supports
  Own-client discovery only for missing protected-resource metadata, never malformed,
  conflicting or unavailable metadata. Review then found raw invalid issuers could
  escape partial results; the new red test failed before validating issuer input
  ahead of all I/O. Oversized, invalid UTF-8, userinfo, query, fragment and HTTP
  issuers are rejected with a fixed error.
- A separate suspended-runner regression reproduced success accepted after the
  overall deadline. Jobs now record an absolute admission deadline and check it
  when handling a result, regardless of queued timer order.
- Five composed lifecycle tests pass: caller death and timeout while DNS/HTTP
  callbacks are held, and application runner restart retiring its task supervisor,
  operation and nested I/O. Test helpers use acknowledgements and process monitors;
  the deadline regression uses an actual timer boundary, not a sleep.
- The first lifecycle fixture had a syntax error, then static type warnings from
  comparing macro-expanded constants. Both were fixed before acceptance. A focused
  format command used root paths from the child directory and matched no files;
  rerunning with child-relative paths succeeded without changing unrelated files.
- Latest full MCP suite: 153 tests, zero failures, seven exclusions. Console:
  476 tests, zero failures, 32 exclusions. Root format, warnings-as-errors compile,
  strict Credo and unused-dependency checks pass. Logs are
  `vxpipe-discovery-mcp-suite.log` and `vxpipe-discovery-console-suite.log`.
  The last full umbrella run predates these changes; final root acceptance remains
  required by T8. No UI changed in this checkpoint.
- Independent GPT-6 Astra xhigh adversarial review of the exact 22 staged files
  reports no remaining blocking findings. Foundation dependencies are limited to
  staged modules, committed connection checks and pinned dependencies. Review was
  source-only; test evidence above was produced separately by the implementation run.
