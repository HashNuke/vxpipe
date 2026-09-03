# Samples development playground

## Goal

Add a frontend-only Vite playground for exercising Vxpipe gateway protocols,
run it alongside the Elixir umbrella with Goreman, and record the relevant
Pipecat React documentation in `AGENTS.md`.

## Findings and decisions

- One `mix run --no-halt` invocation at the umbrella root starts both the
  `call_engine` and `gateway` applications. Goreman therefore owns one Vxpipe
  BEAM process rather than running the two OTP applications in separate VMs.
- The published Voice UI Kit console template is intended for development and
  exposes conversation, transport state, metrics, device controls, and RTVI
  events. It is a better initial playground than duplicating those controls.
- The console requires the Pipecat core client, React client, and a concrete
  transport. The first sample uses Small WebRTC and a configurable
  `/api/rtvi/offer` URL. This is a frontend integration point, not an assertion
  that the generated gateway skeleton already serves that endpoint.
- Vite proxies `/api` to `http://127.0.0.1:4000` by default. The proxy target and
  browser-visible offer URL can be overridden independently without placing
  credentials in source control.
- Pipecat UI dependencies are kept in `samples/package.json`; they are not Mix
  dependencies and do not change umbrella dependency direction.

## Red-green evidence

- Red: `npm test --prefix samples` failed because `src/App.tsx` did not exist.
  This established the owned contract that the sample configures the Pipecat
  console for Small WebRTC at `/api/rtvi/offer`.
- Green: `npm test --prefix samples` passed the focused integration test.

## Verification

- `npm run build --prefix samples` passed TypeScript checking and the Vite
  production build against the installed Pipecat packages. The full console
  currently produces a roughly 1.09 MB minified main chunk before gzip; this is
  acceptable for the development playground but should be revisited before it
  becomes a user-facing application.
- `bash -n bin/dev` passed.
- `goreman ... check` reported a valid Procfile with `samples` and `vxpipe`.
- A live `bin/dev` smoke test showed both Goreman processes running and returned
  HTTP 200 from `http://127.0.0.1:5173/`. The processes terminated cleanly on
  interrupt.
- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed with four tests across the umbrella.
- `mix deps.unlock --check-unused` passed.
- `npm ls --prefix samples --depth=0` resolved all declared dependencies.

## References consulted

- Pipecat React SDK overview, components, and hooks documentation.
- Pipecat Voice UI Kit quickstart, styling, and console template documentation.
- Published npm package metadata for the Pipecat clients, Voice UI Kit, and
  Small WebRTC transport.
