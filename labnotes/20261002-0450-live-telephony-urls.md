# Live telephony test URLs

## Goal

Make the Twilio and Telnyx live dial tests need one public origin instead of four
hand-written webhook and media URLs, and document what each setting means.

## Decisions

- Added a test-only `TELEPHONY_TEST_PUBLIC_URL`. Did not reuse `APP_HOST` or
  `TELEPHONY_HOST`: `config/runtime.exs` reads those at boot for the whole test
  run, which would enable the gateway telephony HTTP listener and change Console
  binding for every test, not only the live dial tests.
- The tests build per-call URLs with `TestTelephonyServiceRepository.configured/1`
  and each provider's `PublicEndpoint`, so they use the gateway's real route
  shapes (`/api/telephony/<provider>/<ingress>/events|media/...`,
  `/webhooks/tenants/<key>/telnyx`) and always use `wss://` for media. The old
  example's `https://todo` placeholder for media was wrong for Twilio, whose
  TwiML builder only accepts `wss://`.
- `TELNYX_PUBLIC_KEY` is now required for the Telnyx lane because the configured
  Telnyx service carries it; the planned webhook-receipt check will use it to
  verify signatures.
- The provider portals' own webhook URLs are only fallbacks: Twilio receives
  `StatusCallback` and inline TwiML per call, Telnyx receives `webhook_url` and
  `stream_url` per call.

## Evidence

- `test/shell/live_provider_runner_test.sh` failed before the runner change
  (placeholder `TELEPHONY_TEST_PUBLIC_URL` and ambient `TELNYX_PUBLIC_KEY` not
  cleared), then passed.
- Offline URL construction in `MIX_ENV=test` with base
  `https://vxpipe-live.example.com/prefix` produced the expected https event and
  wss media URLs for both providers.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix deps.unlock --check-unused` passed.
- Gateway suite: 522 tests, 0 failures (7 excluded).
- Umbrella `mix test` could not run here: the persistence test database
  connection failed for lack of a password (`VXPIPE_TEST_DATABASE_URL` not set).
- No live call was placed; no credentials are configured in this checkout.

## Next

- Start the gateway HTTP endpoint with in-memory services on a fixed port in the
  live tests and assert a verified provider webhook arrives before hangup.
- Needs a public hostname with a trusted TLS certificate forwarding to that port.
