# README quick start

## Direction

- The user wants the root README to introduce the product and help a new reader
  get started quickly. The existing 194-line README opened with a placeholder
  and mixed setup with transport, supervision, persistence, and release details.
- Replace it with a short product introduction, concrete capabilities, one local
  voice-demo path, and links to further guides. Describe implemented features
  without performance claims or implying a packaged release is available.
- Preserve the previous technical material in `docs/development/local-development.md`, organize it
  with focused headings, and adjust relative links. Keep provider configuration
  before the launch command. Keep CI details out of the README as requested
  earlier in the session.
- Use the existing direct `mix run --no-halt` launch with `APP_HOST=localhost`
  and HTTP. This avoids requiring Goreman, Watchman, or Tailscale for a first
  local demo. The full development stack remains documented separately.
- Read the Mix asset aliases, runtime host/TLS/provider settings, development
  sample prompts, Console routes, and existing manual call walkthroughs to ground
  the commands and examples. The default sample supports the time tool and
  agent transfer to billing; PostgreSQL is optional for this path.
- Documentation-only checkpoint: no new behavior test or milestone update is
  needed. No application code or configuration changes are intended.

## Verification

- The README is now 52 lines. Reviewed its product claims against the existing
  sample configuration and implemented call/tool/transfer features.
- All nine relative documentation links and heading anchors resolve. All ten
  shell snippets across the README and development guide parse with `bash -n`.
  The referenced `.env.example` exists; its contents were not read or logged.
- Read `mix help run` and verified the direct launch on an unused localhost port
  with the documented local fixture/Morse profile and no provider keys or
  PostgreSQL configuration. The server returned HTTP 200 from `/healthz`,
  `/pipecat-console`, and `/assets/app.js`; the latter two contained their expected
  page/bundle content. The development applications compiled during startup.
  Stopped only the temporary verification process group afterward.
- This verifies application startup and asset serving, not a rendered-browser
  interaction or a live Gemini/Deepgram call. The live voice instructions were
  checked against the existing sample configuration and manual walkthroughs.
- `git diff --check` passed. Scope is the README, the relocated development
  material, and this labnote; no application code, configuration, or dependency
  changes.
