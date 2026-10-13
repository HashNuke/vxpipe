# Remove Users subtitle

- Removed the redundant installation/tenant-access subtitle from UsersPage,
  including its loading story. Kept Create user aligned to the right after
  removing its sibling text.
- Mechanical copy/layout change: no new behavior tests. Eight existing
  authentication/UsersPage tests passed, as did TypeScript and ESLint.
- Inspected the requested loading story in headless Chrome at desktop 1280px
  and mobile 390px. Subtitle absent; controls remain aligned and fit.
- Umbrella checks could not complete: Mix reports argon2_elixir is unavailable
  in this checkout and requests mix deps.get. No backend files or dependencies
  were changed for this copy edit. Frontend checks and browser review passed.

- User fetched the missing dependency. Retry passed formatting, compilation, and
  Credo; interrupted its test run at the user's request to commit, pull, then
  verify the updated checkout.

## Pull and verification

- Committed the subtitle removal, then pulled origin/main. Resolved the one
  UsersPage conflict by retaining the remote Users heading and canonical /users
  navigation while omitting the removed subtitle. Completed the merge.
- Four newly pulled application tests used the subtitle as their page-ready
  assertion. They failed as expected; updated them to use the Users level-one
  heading. Full frontend suite then passed all 703 tests.
- Post-pull gates passed: format, warnings-as-errors compile, strict Credo,
  3,777 umbrella tests with zero failures, unused dependency check, TypeScript,
  ESLint, and Console esbuild. Argon2 dependency now builds successfully.
- Rechecked the merged Users loading story visually. Restarted Storybook on
  port 6006 and confirmed HTTP 200.
