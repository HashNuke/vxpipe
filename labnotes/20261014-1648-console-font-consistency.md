# Console font consistency

## Findings and decisions

- User wants one consistent UI font, following existing shadcn components, and
  explicitly allows retaining monospace. Keep established Inter and Geist Mono.
- Earlier inspection missed the Fontsource imports in Storybook preview. Storybook
  already bundled the fonts; production Console did not. Corrected this finding
  in the user update.
- Console now owns Fontsource dependencies. Shared fonts.css imports Inter weights
  400/500/600/700/800 and the existing Geist Mono 400; display swap and Unicode
  ranges come from Fontsource. Browser requests only needed subsets and weights.
- Shared typography.css defines --font-sans. Regular Console styles, shadcn
  font-sans utilities and service-logo fallback lettering use that choice.
- Production entry styles and Storybook share font loading. Esbuild emits hashed
  WOFF/WOFF2 assets; Tailwind receives the token separately, avoiding broken font
  URLs in its standalone output. Existing monospace selectors stay unchanged.
- Persisted the sanctioned Inter exception through impeccable hooks ignore-value;
  .impeccable is intentionally Git-ignored by existing user policy. No forced add.

## Verification

- mix assets.build passed; no generated assets staged.
- 736 frontend tests, TypeScript and ESLint passed.
- Chrome rendered role details at 1440px and 390px and the call spec editor at
  1440px. Visible controls and headings use Inter; layouts remain intact.
- Served built production assets independently of Storybook. Loaded Inter and
  Geist Mono font faces successfully; local font requests returned HTTP 200.
- An initial h1 probe selected Storybook's hidden No Preview heading (Nunito Sans).
  Verified the visible Console heading uses Inter; no application-font defect.
- Focused typography detector returned no findings. Root formatting, compilation,
  strict Credo and unused dependencies passed. Full suite: 3,790 tests, one speech
  deadline timing failure (300ms DOWN assertion). All 14 deadline tests passed on
  isolated rerun without code changes; all other application suites passed.
