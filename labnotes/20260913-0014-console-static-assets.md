# Console static assets

## Goal

Replace Console's compile-time CSS and JavaScript embedding with ordinary esbuild outputs served
by the existing Phoenix endpoint. Preserve the React sample, call-inspection, sign-in, diagnostics,
and LiveView behavior and appearance. This is a pre-delivery cleanup, not container or retention
work.

## Initial findings

- Console already owns an esbuild watcher and serves `priv/static/assets` through `Plug.Static`.
- `CallInspectionAssetController` nevertheless embedded a standalone stylesheet plus complete
  Phoenix and LiveView browser libraries into an Elixir module.
- `DiagnosticsAssetController` embedded a second copy of the same browser libraries and its hook.
- `DiagnosticsLayout` also contained roughly 400 lines of inline CSS, giving the Elixir layout a
  separate presentation responsibility.
- The custom routes existed to provide content-addressed immutable responses, but the existing
  sample assets already use stable esbuild output paths with HTTP revalidation. That bespoke
  controller path is not required for either LiveView surface.

## Plan

1. Compile the React sample, shared LiveView bootstrap, call-inspection CSS, and diagnostics CSS as
   independent esbuild entries.
2. Keep the diagnostics-only `MetricPulse` hook in the shared LiveView bundle; it is inert on pages
   without a matching `phx-hook`.
3. Let both LiveView roots select their existing socket through the `phx-socket` HTML attribute.
4. Serve all outputs through the endpoint's existing `Plug.Static` and remove both asset
   controllers and their routes.
5. Verify project-owned bootstrap behavior, rendered asset references, frontend build/tests,
   focused Console tests, root gates, and real desktop/mobile browser rendering.

## Red evidence

The first focused Console run produced exactly two intended failures: call inspection still linked
the content-hashed controller route, while diagnostics still embedded CSS and linked its custom JS
route. The new frontend test failed before collection because `src/live.ts` did not yet exist. This
establishes both the Phoenix-rendered asset contract and the shared browser bootstrap as new
project-owned behavior before implementation.

## Implementation

The single esbuild profile now uses named inputs so the existing sample keeps `app.js`/`app.css`
while producing `live.js`, `call_inspection.css`, and `diagnostics.css`. The official Phoenix
1.8.13 and LiveView 1.2.11 browser packages are pinned in the frontend lockfile to match the current
Hex dependency versions; `@types/phoenix` supplies the missing Phoenix client declarations.

`src/live.ts` owns the shared client bootstrap. It validates the CSRF token and page-selected
`phx-socket`, registers the existing `MetricPulse` hook, connects one `LiveSocket`, and exposes it
for the usual browser debugging. Module scripts are deferred by browser semantics, with a guarded
already-loaded path as well. Both prior asset controllers and both custom routes are removed.

The Diagnostics stylesheet was mechanically extracted from its inline HEEx block without changing
its rules. The design hook consequently saw previously shipped literal values for the first time.
Those exact values were retained as sanctioned existing-surface exceptions rather than changing
the visual design during an asset refactor; the narrow value ignores and rationale are stored in
the shared Impeccable configuration.

## Green evidence

- The shared bootstrap test passes and confirms dynamic socket selection, CSRF propagation, hook
  registration, connection, and browser debug exposure.
- All ten frontend tests pass.
- `mix assets.build` passes TypeScript validation and produces all five expected outputs.
- The focused call-inspection and diagnostics files pass 29 tests, including the new static-asset
  references and absence of inline Diagnostics CSS and legacy controller URLs.
- The complete Console suite passes 93 tests.
- `mix assets.deploy` completes and emits minified `app.js`, `live.js`, `app.css`,
  `call_inspection.css`, and `diagnostics.css` outputs.
- A temporary fixture-backed Console served both operator surfaces through the real endpoint.
  Chromium connected the diagnostics LiveView through `/diagnostics/live`; requests for the shared
  module and both stylesheets returned normally and revalidated on repeat navigation.
- Diagnostics and operator sign-in were rendered at 1440×1000 and 390×844. All four states had
  matching viewport, body, and document widths, no browser errors, and zero axe violations or
  incomplete findings. The extracted rules preserved both surfaces' existing appearance.
- The final design detector reports no findings after recording narrow sanctioned ignores for the
  unchanged Diagnostics literal values exposed by moving its inline stylesheet into `assets/css`.
- The root formatting check, warnings-as-errors compilation, full 996-test umbrella suite with 15
  explicitly excluded integrations, unused-dependency check, and strict Credo pass. Credo checks
  801 source files and reports no issues.
