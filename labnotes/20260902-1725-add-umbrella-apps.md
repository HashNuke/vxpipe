# Add umbrella apps

## Goal

Scaffold `gateway` and `call_engine` as children of the Vxpipe umbrella.

## Decisions

- Generated both children with supervision trees because they are runtime OTP
  applications rather than library-only packages.
- Kept labnotes tracked so this implementation record can be committed with the
  work it documents.
- Did not introduce a dependency between the children because no dependency
  direction has been specified.

## Progress

- Generated `apps/gateway` with `mix new apps/gateway --sup`.
- Generated `apps/call_engine` with `mix new apps/call_engine --sup`.
- Confirmed both child projects use the umbrella's shared build, configuration,
  dependency, and lockfile paths.

## Verification

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed for both children.
- `mix test` passed with one doctest and one test in each child.
- `mix deps.unlock --check-unused` passed.
