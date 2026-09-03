# Create-room vertical slice

## Goal

Implement the smallest complete path from the samples browser through the HTTP
gateway into the OTP call engine: create a logical room, start one supervised
room incarnation, and return its public snapshot.

## Scope decisions

- `POST /api/rooms` is a development-playground operation for this checkpoint.
- The gateway injects a configured development principal. Request data is not
  treated as authenticated tenant or actor identity.
- The engine command and snapshot are protocol-neutral and contain no RTVI or
  HTTP terms.
- A room incarnation is a supervised failure boundary. Its authority is not
  independently restarted, and the incarnation is not automatically recreated.

## Progress

- Created focused call-engine, gateway, and browser tests before implementation.
- Red: the call-engine test could not compile because the command, error, and
  snapshot contracts did not exist.
- Red: the gateway returned its existing `404` for `POST /api/rooms`.
- Red: the browser test could not find the create-room control.
- Green: the call engine creates a room with a distinct incarnation, returns a
  serialization-safe snapshot, rejects duplicate logical room identity, and
  rejects an elapsed command deadline.
- Green: terminating the authority produces monitored `:DOWN` messages for both
  the authority and its incarnation supervisor, and removes the registry entry.
- Green: the gateway returns `201` JSON using its configured principal and keeps
  the operation unavailable when disabled.
- Green: the samples UI starts on a dedicated creation screen and mounts the
  uncluttered Pipecat console only after `/api/rooms` succeeds.

## Implementation notes

- The call engine generates opaque command, room, and room-incarnation IDs with
  fixed prefixes and cryptographically strong random bytes.
- The named room registry keys logical rooms by `{tenant_id, room_id}`. The
  named dynamic supervisor is the only path that starts incarnation children.
- `RoomAuthority` owns the initial snapshot. Its child specification is
  temporary and significant, while the incarnation supervisor uses
  `auto_shutdown: :any_significant`; this prevents an authority-only restart.
- Gateway configuration owns the development tenant, actor, and scope. The
  browser can select only a bounded, URL-safe room ID; that ID is not a secret
  or an authorization credential.
- The browser generates one stable `room_` ID with `crypto.randomUUID()` for the
  creation-screen attempt and sends it as JSON. The server validates the ID and
  remains authoritative for uniqueness and room lifecycle.
- Elixir's standard `JSON` module serializes the gateway response, so the slice
  required no new external JSON dependency.
- The room creator is a dedicated responsive screen. Successful creation
  replaces it with the Pipecat console rather than adding controls or metadata
  around the third-party responsive surface.

## Barriers and corrections

- The first engine compile exposed a private builder with the same name and
  arity as the public snapshot call. Renaming it to `build_snapshot/2` resolved
  the conflict.
- The frontend test file imports Vitest hooks rather than enabling global test
  APIs, so React Testing Library did not install automatic cleanup. Explicit
  cleanup prevents rendered applications from leaking between tests.
- A process `:DOWN` can reach the test before Registry has removed its ETS
  entry. Synchronizing with the named Registry through `:sys.get_state/1`
  provides deterministic ordering without a timing sleep.
- A user-started `bin/dev` stack from before this change still occupied the
  standard ports. It was left untouched. The new gateway and engine were started
  together on temporary loopback port 4001 for the live application request.

## Verification

- The focused call-engine suite passes three tests covering creation, duplicate
  identity, elapsed deadlines, and whole-incarnation termination.
- The focused gateway suite passes seven tests, including client room-ID
  validation, `201` JSON creation,
  configured-scope authorization, and a `404` when the development slice is
  disabled.
- A live `POST /api/rooms` on the temporary listener preserved the supplied
  browser-style `room_` ID and returned engine-generated `rinc_` and `cmd_`
  identifiers with the configured development tenant, actor, and `open`
  lifecycle. A request without a room ID returned `400`. The temporary listener
  was stopped.
- The samples suite passes two tests, including the browser request and the
  creation-screen-to-Pipecat transition.
- The Impeccable onboarding playbook guided the separate-screen flow. One
  desktop/mobile inspection found that entrance blur could make the initial
  frame muddy; the correction removed blur while preserving reduced-motion-safe
  position and opacity movement. The single confirm pass was crisp at both
  viewport sizes.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`,
  `mix deps.unlock --check-unused`, and production compilation passed.
- The samples TypeScript/Vite build and dependency-tree check passed. The
  existing large-chunk advisory remains.
- Shell syntax, Caddyfile formatting, and `git diff --check` passed.
