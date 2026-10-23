# Morse endpoint and deployment plan

The user requested milestone details for a configurable local Go API endpoint,
later switching to the deployed Railway service, and preparation of the separate
Go app for deployment. Provider labels remain `MorseCodeApiTTS` and
`MorseCodeApiSTT`.

Inspected the milestone index, existing milestone and architecture document, and
the Go project's Railway runbook. The worktree already contains implementation
changes and progress evidence. This update preserves those changes and edits
only the milestone plus this planning note; it does not claim new runtime or
hosted acceptance.

The existing specification already defines `MORSE_CODE_API_BASE_URL`, private
HTTP/WS origin resolution, localhost testing, container packaging, readiness,
shutdown, DNS, user-owned deployment and rollback. Added an explicit four-stage
delivery table and a handoff-record task so prerequisites and evidence are easy
to locate. Local work does not wait for Railway. The override remains available
through deployment and verification, and switching requires a Vxpipe restart.

Design review: A–G own local provider behavior; H and I preparation own the
verified deployment package; I hosted verification follows the user's deployment.
G rehearses origin switching locally before I repeats it remotely. No provider
IDs, persistence requirements, API scope or existing progress boxes changed.
The new handoff-record task remains unchecked.

Rechecked official Railway documentation for
[readiness and injected PORT](https://docs.railway.com/deployments/healthchecks),
[public domains](https://docs.railway.com/networking/public-networking), and
[current IaC](https://docs.railway.com/infrastructure-as-code). These support the
existing deployment requirements; configuration is not evidence of a deployed
or continuously monitored service.

Verification: checked Markdown relative file links, balanced code fences,
checkpoint ordering and whitespace. Documentation-only update; no application
tests or deployment were performed for this revision.
