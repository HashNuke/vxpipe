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
