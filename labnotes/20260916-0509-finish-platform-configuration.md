# Finish platform configuration

## Final scope audit and documentation checkpoint

- Independent GPT 6 Astra xhigh audit confirms the supported catalog is Google, Deepgram,
  Zenmux, Telnyx and Twilio with their existing auth shapes. Model fixtures and Morse speech
  remain credential-free. No new provider work is needed.
- No production provider-env reader, capability-profile registry, `provider_api_key_environment`,
  `VXPIPE_CONFIG` or `vxpipe_config` dependency remains. Internal explicit-key adapters, transport
  settings, MCP application scopes, call-duration defaults and llm_db's TOML parser are valid.
- Remaining dormant carrier application-scope branches will be deleted with rejection tests.
  The stale `.env.example` will be retired; visible `env.sample` is the sole sample.
- Updated architecture's current inline/opening/carrier credentials and private owner handoff.
  Qualified the obsolete original Jido/profile/runtime narrative as historical. Hosted admission
  requires persistence; explicit embedding is distinct from a database-outage fallback.
- Updated the Docker preview and held delivery specification to platform env plus tenant DB.
  Removed the proposed deployment JSON loader; JSON remains call-definition data. Added the
  credential milestone prerequisite while retaining the packaging hold and library boundaries.
- Independent documentation review found stale index counts, residual application-wide routing,
  registry handoff and mounted-JSON claims. Corrected them and distinguished model fixtures from
  Morse speech. Documentation verification: reviewed diff, Markdown links and `git diff --check`.

## Database design review

- Select the two approved URL/pool alias pairs independently, ignoring blank values. Development
  defaults to local vxpipe_dev and pool 10; production has no implicit DB. Test mode ignores all
  normal aliases so Sandbox stays isolated, including with invalid ambient values.
- Reuse Ecto URL validation while sanitizing exceptions. Independent review found Ecto merges
  URL query parameters after explicit Repo options: a query pool_size could override the selected
  pool. The implementation must preserve alias/default pool authority and verify effective Repo
  configuration. Tests are drafted outside the test tree while the prior full suite runs.

## Carrier scope removal

The constructor rejection test first failed because application-scoped credentials were accepted
(6 tests, 1 expected failure). Calls route rejection first reached an unconfigured repository
instead of rejecting scope (7 tests, 1 expected failure). Removed the accepting carrier branches
and narrowed port types; tenant route/conflict assertions remain. The media negative test now
constructs an intentionally invalid identity rather than using the constructor to accept it.
Gateway 38 focused tests, Calls 13 and Persistence 10 pass. No migration is needed.

## Database aliases

Five new configuration tests failed against the retired reader, then pass with the approved alias
selection. Invalid values fail with setting names only; test DB/Sandbox ignore ordinary aliases.
The effective Ecto configuration test includes a conflicting URL pool_size and verifies both the
independent default 10 and selected 7. Runtime strips that query field before existing Ecto parsing.
The existing Console configuration group passes 15 tests and the Persistence group passes 10.
All runtime environment reads remain in runtime.exs. The stale hidden sample is deleted and the
visible sample documents both alias pairs. Source boot/restart evidence follows below.

## Source boot and fresh-VM verification

With all four database aliases and both retired names unset, the macOS development apps booted
using vxpipe_dev and pool 10. Existing migrations were applied. A transaction provisioned an owned
synthetic Google/Deepgram tenant, saved/published the actual development definition and prepared a
call. A fresh VM fetched that call and constructed the real Google model and Deepgram TTS
configurations from its exact persisted tenant values despite conflicting legacy provider env keys.
Both runs booted the Console composition with HTTP listeners/watchers disabled, so no browser or
live provider call is claimed. The acceptance script then removed only its owned synthetic tenant
and dependent records. Log: `tmp/platform-default-boot.log`.

The existing configuration regression also supplies a malformed legacy TOML file through
VXPIPE_CONFIG; the removed reader cannot affect inline configuration. No parser dependency or
fallback was reintroduced. Current operational docs explain explicit new-revision publication and
fresh preparation; historical plans remain intact and invalid old activations reject.

Final format, warnings-as-errors compile, strict Credo and unused-lock checks pass. Independent
GPT 6 Astra xhigh review found no production/test blocker; its two remaining documentation
clarifications are corrected. Final complete-milestone root regression remains to run.
