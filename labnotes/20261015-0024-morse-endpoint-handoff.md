# Morse endpoint handoff

The endpoint/Railway planning follow-up clarifies the existing configuration
handoff table with derived WS/WSS origins, distinguishes production TLS from
development HTTP, and explains that Railway's internal port is not part of the
public origin. Cutover and rollback retain the same build, saved call specs and
service credentials.

Inspected Vxpipe's runtime loader and the separate Go project's deployment
runbook, environment example and isolated Railway IaC module. They already
provide the setting names and listener behavior used by the plan. The matrix
does not claim new runtime coverage. Existing uncommitted STT integration work
was preserved; this checkpoint changes documentation only.

Rechecked Railway's official
[healthcheck documentation](https://docs.railway.com/deployments/healthchecks)
for injected `PORT` and readiness semantics, and its
[configuration reference](https://docs.railway.com/config-as-code/reference)
for the existing legacy-file deprecation. The milestone retains its current
IaC approach. No Railway account operations or deployment were performed.

Design review: local configuration and TLS rehearsal stay in F/G, packaging and
the concrete user handoff stay in I, and hosted acceptance follows deployment.
The configuration table is explanatory, not a second progress checklist. Existing
completion statuses are unchanged. The handoff gate now explicitly records
actual nonsecret values, their process ownership and the process-manager restart
command, preventing an ambiguous instruction to restart only the Go service.

Verification: relative document links, balanced code fences and whitespace
checked; runtime setting names compared with source. No application tests were
needed for this documentation-only revision.
