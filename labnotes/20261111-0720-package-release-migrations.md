# Package release migrations

## Decision and scope

- The user approved a packaged `bin/migrate` command and pointed out that
  `mix phx.gen.release` supplies it. Used that generator from the Console child
  because Phoenix does not run this generator at an umbrella root.
- Moved its helper to `Vxpipe.Persistence.Release`, using `:vxpipe_persistence`
  and its configured `ecto_repos`. Moved the executable script to the umbrella's
  `rel/overlays/bin/migrate` and changed its release executable to `vxpipe`.
  The helper retains Phoenix's standard migration and rollback implementation.
- Removed unused generated server/Windows scripts; this task adds the Linux
  migration command to the existing release. No dependency or runtime
  configuration changes are needed.
- The user rejected redundant automated coverage of Phoenix/Ecto migration
  machinery. Removed the newly added integration test and verified the actual
  built artifact with disposable-database commands instead.
- The schema comes from the persistence application's existing versioned
  migration files, included by Mix in the release's `priv/repo/migrations`.
  Ecto records applied versions in `schema_migrations`. A PostgreSQL database
  must already exist. No SQL dump or host-side Elixir installation is required.
- Documented `/app/bin/migrate` as the container command: a host invokes it with
  `docker run --rm --entrypoint /app/bin/migrate` using the new image and runtime
  environment, or `docker exec` for an existing container's installed version.
  Railway uses the same path as its pre-deploy command. Container publishing and
  the full delivery milestone remain separate.

## Verification

- Built a production release with the overlay script included and executable.
- From a working directory outside the release, applied all 57 migrations to an
  empty disposable PostgreSQL database; exit 0 and first-run installation state
  present. A second invocation exited 0.
- Invoked the same release helper and confirmed the persistence application,
  Oban, Console, Gateway and call engine were absent from started applications.
- Invoked `/app/bin/migrate` from Docker using the built release mounted at
  `/app` in an existing local Ubuntu 26.04 image, with the PostgreSQL Unix socket
  mounted and networking disabled. Exit 0. This verifies the host/container
  invocation; no Vxpipe container image was built or published.
- Dropped the disposable database and invoked the command again: exit 1.
  The normal QA database and environment files were not inspected or changed.
- Rebuilt the normal QA release, changed the user service's `ExecStartPre` to
  `bin/migrate`, and restarted it. Migrations reported already up. The service is
  active; HTTPS `/healthz` returns 200 and HTTP redirects to HTTPS with 308.
- Formatting, warnings-as-errors compilation, strict Credo and the unused-lock
  check passed. Shell syntax and changed documentation link targets passed.
- The umbrella suite finished: 5,216 tests, 1 failure, 376 excluded (exit 2).
  Every other application passed. Seed 596943 reproduced the STS transfer
  readiness assertion recorded before this checkpoint in the
  [QA release labnote](20261111-0641-run-qa-release.md): `push_text/2` received
  `{:error, :held}` after the failure event. This checkpoint changes no speech or
  transfer code; the migration artifact checks above all passed.
