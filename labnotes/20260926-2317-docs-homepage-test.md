# Docs homepage test

Date: 2026-09-26. Starting revision: `68fa5a56`.

## Finding and change

- Package 10 / R10-2 covers the docs site homepage test. The existing test
  expected three hero actions and thirteen feature cards from an older page.
  `node --test test/homepage-structure.test.mjs` failed red at the three-action
  assertion; the current page has two actions.
- Updated the test to check the current two hero actions, four trust badges,
  ordered top-level sections, four feature groups, and the quickstart guide
  link. Kept the passing landing-backdrop check. Removed brittle old feature
  copy and card-count assertions, which no longer described the page.

## Verification

- Focused docs site file: two tests, zero failures after the edit. The whole
  docs site `node --test` lane passed five tests, zero failures.
- No rendered UI change; only the test file changed.
