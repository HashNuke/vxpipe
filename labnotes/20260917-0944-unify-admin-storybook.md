# Unify admin Storybook

## Decision

The operator admin stories belong in the existing `@vxpipe/react` Storybook. The Console asset
package continues to own the admin components, stories, tests, and Storybook type dependency, while
`packages/react/.storybook` owns the only Storybook server and preview configuration.

The shared Vite configuration deduplicates React and loads Tailwind for the Console-owned stories.
The admin stylesheet declares its story/component directory with Tailwind's `@source` directive;
without that directive the unified server loaded the stories but emitted none of their utility
classes.

The Admin source keeps its own runtime dependencies. A clean setup therefore installs both the
root npm workspace and `apps/vxpipe_console/assets`, then builds the local packages before starting
the shared Storybook. This avoids copying Console-only dependencies into `@vxpipe/react`.

## Rejected alternative

A second Storybook under `apps/vxpipe_console/assets` was removed. It split the debug console and
admin review flows across ports and duplicated fonts, preview settings, Storybook scripts, and
build dependencies.

## Verification

- Console assets: 54 Vitest tests passed; TypeScript check and ESLint passed.
- Package workspace: 34 Vitest tests passed; both npm packages built.
- Unified Storybook production build completed successfully. Vite reported only dependency
  `use client` and chunk-size warnings.
- A copy without `node_modules`, package `dist` output, or Storybook output completed both clean
  npm installs, built `@vxpipe/core` and `@vxpipe/react`, and built the unified Storybook.
- Headless Chrome rendered `Admin / Full journey / Review Flow` with the dark admin styling at the
  same server that exposes `Prototype / Workbench`.
- The normal port, 6006, was occupied by an unrelated `topics.club` Storybook during verification,
  so the Vxpipe server was inspected on 6007 without stopping the other project.
