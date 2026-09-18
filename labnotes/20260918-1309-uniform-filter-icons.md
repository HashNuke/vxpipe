# Uniform filter icons

## Goal

Use semantic state colors for conversation filter icons and align credential preview typography.

## What I tried

- Added focused render tests before changing each component.
- Removed filter-specific color classes and used the existing green/muted tokens for enabled and disabled states.
- Moved credential preview font size, font family, and muted color to the row shared by its label and value.

## What worked

- The filter regression test failed against the category-specific classes and passed after the shared active class was introduced.
- The services test failed while the credential row lacked shared typography and passed after the row inherited one treatment.

## What did not work

- The existing Storybook process on port 6006 retained stale package output during the first browser pass. Verification therefore uses a fresh Storybook process after rebuilding `@vxpipe/react`.

## Decisions

- Enabled conversation filters use signal green; disabled filters use the theme's muted grayscale token.
- Credential labels retain uppercase/weight for scanning, but labels and masked values share `font-mono`, `text-xs`, and `admin-muted`.

## Verification

- `npm test -- --run packages/react/test/console.test.tsx`: 25 tests passed.
- `npm test -- --run src/admin/TenantServicesPage.test.tsx`: 6 tests passed.
- Console asset TypeScript check and ESLint passed.
- Root TypeScript/build check passed after rebuilding `@vxpipe/react`.
- Restarted Storybook on port 6006 and inspected the ended-call story at 1440×900 and 390×844.
- Browser-computed filter colors: enabled `oklch(0.78 0.12 162)`; disabled `oklch(0.76 0.01 286)` in dark mode, including the compact menu.
- Browser-computed Account SID label/value styles both use 12px monospace and `oklch(0.76 0.01 286)`.
- Root frontend suite: 40 tests passed.
- Console frontend suite: 132 tests passed.
