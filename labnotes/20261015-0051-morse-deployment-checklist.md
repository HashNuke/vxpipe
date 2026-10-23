# Morse deployment checklist

Updated the existing milestone for the requested configurable local endpoint
and later user-owned Railway deployment. Preserved the MorseCodeApiTTS and
MorseCodeApiSTT names, current implementation evidence and unchecked acceptance
gates. No application code or deployment was changed.

Added a concrete deployment artifact inventory and clarified ownership of Go
listener variables versus Vxpipe's MORSE_CODE_API_BASE_URL. The smoke runner
must require an explicit origin, fail nonzero on failed checks, identify failed
transports without keys, and never fall back to a hosted service. Returning to
local development after deployment remains part of the documented workflow.

Design review: local development and container preparation precede user
deployment; hosted acceptance remains separate. These refinements elaborate
existing F/G/I contracts and do not add a competing progress checklist or mark
unverified work complete. Preserved the existing unrelated room-boundaries note.

Rechecked the official Railway [Dockerfile guide](https://docs.railway.com/builds/dockerfiles)
and [healthcheck guide](https://docs.railway.com/deployments/healthchecks).
The existing milestone retains those references for build and injected-port
requirements. Verification covers whitespace, relative links and Markdown fences;
application tests are unnecessary for this documentation-only change.
