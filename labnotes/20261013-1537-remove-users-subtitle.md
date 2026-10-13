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
