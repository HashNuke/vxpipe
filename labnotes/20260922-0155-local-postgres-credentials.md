# Local PostgreSQL development credentials

- Bare `mix ecto.migrate` failed before this change: the development URL lacked
  credentials and local PostgreSQL requires a password for TCP connections.
  Supplying `PGUSER=postgres PGPASSWORD=postgres` made the same command succeed.
- The sibling development projects put `postgres`/`postgres` in their development
  Repo configuration. Added those two options to `config/dev.exs`, leaving the
  existing database URL, alias precedence, production configuration and test
  configuration unchanged. Documented the local defaults in `docs/development/local-development.md`.
- Bare `mix ecto.migrate` now exits successfully with `Migrations already up`.
  Format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass. The full umbrella test suite was stopped at the user's request;
  this checkpoint uses the actual migration command as its behavior check.
