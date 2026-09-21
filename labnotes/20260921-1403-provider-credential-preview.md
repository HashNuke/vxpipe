# Provider credential preview

The provider credential modules now declare ordered, safe preview fields. Calls derives only the
declared last-four hints at create/replace; Console renders the same declarations from metadata and
does not decrypt payloads. Twilio's auth token remains fully masked. Telnyx's optional public key
is accepted in the telephony setup form but omitted from credential inventory previews.

The Console's API-key, Telnyx and Twilio inputs are separate components. Providers with the same
API-key input share one component. The enclosing form retains provider selection, local validation,
Test, Save, clearing and status to avoid changing submission behavior.

Red tests: the provider registry test failed because `preview_fields/0` was absent; the Calls hint
test failed because a provider ID was treated as an auth kind. Both became green after the contract
and consumer changes. Focused provider, Calls and Console endpoint tests passed (6, 19 and 12
tests). Frontend field-form tests and the full frontend suite passed (10 and 189 tests); TypeScript
and lint passed.

Rendered Chrome inspection against the local Console at 1440×900 and 390×844 covered Rime's
API-key form, Twilio's SID/token form, and Telnyx's API/public-key form. Inputs and separate Test
and Save actions were present; the mobile forms had no horizontal overflow. No live credentials
were submitted. The root `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix test` and `mix deps.unlock --check-unused` gates passed. This checkpoint
does not change call media or supervision, so no separate call load test was run.

Final diff review found that the form's generic API-key branch still rendered for an unrecognized
stored provider. A focused UI test first failed on that branch; explicit support for the six current
forms now makes the unsupported case show a message and disables Test/Save. The focused form suite
passed (11 tests), then TypeScript, lint and the full frontend suite passed (190 tests). The browser
pass covered the supported form variants before this final fail-closed branch was added; that branch
was verified with the focused DOM test, not with a persisted unsupported-provider browser fixture.

Rejected storing additional preview data or decrypting during inventory reads because current
bounded suffix hints already support every declared preview. An unsupported provider produces no
hint or preview; it does not select another provider.
