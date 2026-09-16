# React component styling

## Decision

Author `@vxpipe/react` with Tailwind CSS v4 utilities colocated in component TSX and a small
package-owned stylesheet for semantic theme variables, base rules and keyframes that cannot be
expressed clearly as utilities. Build one precompiled CSS artifact for npm consumers. Generate
shadcn registry items from the same component source so registry consumers receive editable TSX,
declared dependencies and the required CSS variables/rules.

The existing monolithic selector stylesheet is prototype debt. Migrate it before expanding the
component set or publishing either distribution. Do not maintain separate npm and registry UI
implementations.

## Why this fits the distribution model

The [shadcn registry](https://ui.shadcn.com/docs/registry) distributes component source, hooks,
configuration and CSS additions. Registry items can declare npm and registry dependencies,
semantic CSS variables, CSS rules and keyframes. The
[shadcn theming contract](https://ui.shadcn.com/docs/theming) recommends semantic CSS variables
mapped to Tailwind utilities and supplies light/dark token and radius conventions.

This gives each distribution a suitable boundary:

- npm consumers import `@vxpipe/react` and its generated CSS artifact; their build does not need
  to discover utility strings inside `node_modules`;
- shadcn consumers install editable TSX and let their existing Tailwind pipeline compile it;
- both consume the same component markup, variants and semantic tokens;
- exceptional CSS remains explicit and small: font loading, theme declarations, keyframes,
  browser pseudo-elements and third-party overrides when unavoidable.

## Rejected alternatives

### Continue the package-wide handwritten stylesheet

The current stylesheet couples unrelated components through global selectors, makes ownership
and deletion difficult, and encourages breakpoint and state rules to accumulate far from the
markup they affect. Prefixing selectors prevents host collisions but does not solve maintenance.

### StyleX

StyleX colocates typed style objects and generates atomic CSS. Its
[style definitions](https://stylexjs.com/docs/learn/styling-ui/defining-styles/) require
ahead-of-time static analysis, and its
[Vite integration](https://stylexjs.com/docs/learn/installation/vite/vite-react) requires the
StyleX compiler plugin before React's plugin. Theme variables must live in dedicated `.stylex.*`
modules, and the documented theming API currently requires `unstable_moduleResolution`.

Those constraints are acceptable for an application or a package that controls its consumer
compiler. They are poor defaults for source-installed shadcn components because installation
would also need to modify each consumer's compiler and lint setup. StyleX would move CSS into TSX
while diverging from the ecosystem we intend to distribute through.

### CSS-in-JS at runtime

Runtime style injection adds a runtime dependency and ordering/SSR concerns without improving the
shadcn installation path. The console needs static, inspectable styles and does not need runtime
theme computation beyond semantic CSS-variable overrides.

## Migration contract

1. Add Tailwind v4 and the minimal shadcn utility stack to the React workspace and Storybook.
2. Define semantic Vxpipe tokens using shadcn-compatible names and map the existing dark-default
   and light themes onto them.
3. Split the console into source-installable component files and move their layout/state styling
   into utility classes. Use a shared `cn` helper and explicit variants where composition warrants
   them.
4. Keep only theme declarations, base rules, keyframes and documented exceptional selectors in
   the stylesheet. Delete migrated `.vx-*` rules checkpoint by checkpoint.
5. Build precompiled npm CSS and prove a package consumer needs no Tailwind source scanning.
6. Build shadcn registry items from the same source and prove installation in a clean Tailwind v4
   fixture, including dark mode, responsive states and dependency resolution.

Do not publish packages or a registry as part of the migration unless publication is separately
requested.
