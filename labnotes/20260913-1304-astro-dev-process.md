# Astro dev process

- Add the docs site's development server to the existing root `Procfile` and
  include `docs` in the processes selected by `bin/dev` in HTTP and HTTPS modes.
  The repository already uses `Procfile` for development; a separate
  `Procfile.dev` is unnecessary.
- Set `ASTRO_DEV_BACKGROUND=0` for this process so Goreman owns its lifecycle,
  including when Astro detects an AI agent environment. Verified the setting
  against the installed Astro CLI and the official
  [background mode documentation](https://docs.astro.build/en/guides/build-with-ai/#background-mode).
- Update development setup with the site's dependency installation command and
  localhost URLs. Keep the docs on local HTTP regardless of the Console's mode.
- Extended the existing shell integration checks first to require `docs` in
  both process selections and its Procfile command. The red run failed because
  the HTTP process selection did not contain `docs`, as expected.

## Verification

- `bash test/bin/dev_test.sh` passed after the implementation, including HTTP
  and HTTPS process selection and the existing reload/TLS checks. Shell syntax
  validation passed. `goreman -f Procfile check` recognizes all three processes.
- Started the real `docs` process through Goreman with its RPC listener disabled
  for this isolated check. Astro stayed in the foreground on localhost:4321 and
  its health endpoint returned `{"ok":true}`. Headless Chrome loaded `/docs/`,
  followed the redirect to `/docs/en/`, and rendered the documentation page.
  Inspected the screenshot; the existing placeholder displayed correctly.
- Closed the verification browser and sent Ctrl-C to Goreman. The process exited
  successfully, and port 4321 had no listener afterward. Full Console startup
  was not needed for this isolated process check; launcher selection is covered
  by the shell integration test.
- All five umbrella completion checks passed with `MIX_ENV=test`: formatting,
  compilation with warnings as errors, strict Credo, tests, and unused dependency
  checking. `git diff --check` passed.
