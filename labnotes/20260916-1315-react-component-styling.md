# React component styling

## Finding

The package-wide `.vx-*` stylesheet has accumulated layout, component state, responsive behavior,
theme values and animation rules. Prefixing limits collisions but does not preserve component
ownership or support an editable-source distribution well.

StyleX was considered because it colocates typed style objects. Official documentation confirms
that it requires ahead-of-time compilation, a Vite compiler plugin ordered before React, statically
analyzable style objects and dedicated `.stylex.*` variable modules. Its theming documentation also
requires `unstable_moduleResolution` at present. That compiler contract is undesirable for shadcn
registry consumers.

Shadcn's official registry can distribute TSX, npm/registry dependencies, semantic CSS variables,
CSS additions and keyframes. Its theming guidance recommends CSS variables mapped to Tailwind
utilities. Tailwind v4 therefore matches the intended source-installable distribution directly.

## Decision

- Author component styles with Tailwind v4 utilities colocated in TSX.
- Keep a small CSS entry for semantic light/dark tokens, base rules, keyframes and unavoidable
  exceptional selectors.
- Emit precompiled CSS for npm consumers and generate shadcn registry items from the same source.
- Migrate the current prototype before expanding the component set; do not create parallel npm and
  registry component implementations.

Durable rationale and migration gates are in `docs/development/react-component-styling.md`.
