# Development login secret

## Decision

Phoenix already configures a development `secret_key_base`. Requiring the same environment variable
again made the default loopback `mix vxpipe.login` workflow unnecessarily fail. The operator login
now uses that checked-in development secret only when both the configured Console host and active
listener are loopback. Production and development exposed on any other host or listener still
require an explicit `SECRET_KEY_BASE`.

## Red-green evidence

- The focused task test first failed with `configure SECRET_KEY_BASE with at least 64 bytes` when the
  explicit secret was absent on `127.0.0.1`.
- After adding the bounded development fallback, the task issues the challenge on loopback while a
  non-loopback HTTPS origin still rejects the fallback.
- GPT-6 Astra xhigh found that development TLS can retain a `localhost` URL while listening on a
  Tailscale address. A new failing regression reproduced that path; the fallback now also requires
  every active listener to use an IPv4 or IPv6 loopback address.

## Verification

- Focused login configuration, task and browser-flow tests: 30 tests, zero failures.
- Console: 155 tests, zero failures, one excluded.
- Final umbrella run: 1,698 tests, zero failures, 39 excluded.
- Formatting, warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
- GPT-6 Astra xhigh approved the listener-aware fallback after re-review.
