# ElevenLabs tool resources

## Withdrawal — 2026-10-01

The user limited ElevenLabs to realtime STT and TTS because hosted-agent STS has
not established compatibility with the existing Gemini/OpenAI contracts. The
uncommitted ToolAPI, AgentAPI tool overload, lease tool extension, loopback server
and associated tests were removed. AgentAPI/lease/request and their existing
tests were restored to their reviewed HEAD content; no commit or Git index was
changed. The already committed agent-only ownership/protocol code remains.

The evidence below describes the withdrawn investigation, not current source
acceptance. Its successful live metadata and residue cleanup observations remain
historical; no live request was repeated. Hosted-agent room STS and call-spec
translation are deferred, not outstanding requirements of the current milestone.
Current pending work is conversational realtime STT and shared final acceptance.

## Starting checkpoint and intent (historical)

HEAD is `50f12631`; agent ownership `58d0be50` is pushed. Full ElevenLabs STT
and room STS were required when this investigation began. Agent creation deprecates inline tools in
favor of independently owned tool IDs. This checkpoint supplies the resource
operation the future call-spec agent configuration needs, preserving the unrelated
user documentation content configuration and deferred gateway implementation.

## Implementation decisions

`ToolAPI` owns bounded client-tool creation, safe returned IDs and reverse
retirement. It validates a closed group of at most 64 unique client tools and
128 KiB of JSON, with response-bearing object parameters. Separate 60-second
preparation/retirement budgets bound request timeouts; the agent lease worker's
shutdown budget increases to 200 seconds to accommodate the resource group.
The controller clears private tool configuration when the request worker starts.

`AgentAPI.with_agent/4` rejects prebound/inline tools, attaches only newly created
IDs and runs checked agent deletion before tool retirement. Partial tool creation,
agent creation/signing/consumer failures and owner death still retire known
resources. A rejected deletion cannot suppress remaining cleanup attempts or
become success. No provider capability or shared speech contract changes here.

## Red-green evidence

- Ten initial group/API tests fail because ToolAPI and with_agent/4 are absent,
  seed 298958; the first implementation then passes the 19 group/agent checks.
- Installed lease integration fails because it ignores private tools, seed 323386
  (19 checks, one failure). Passing the group to the independent request worker
  makes the combined 28 checks pass, seed 495987.
- The first live metadata attempt fails before HTTP: combined Finch and legacy
  connect options are incompatible. An initial diagnostic mistakenly calls a
  private Req function; it is replaced with actual loopback HTTP. Reproducing
  the conflicting options makes that HTTP case fail, seed 283878, then the
  compatible private request copy makes it pass. A location selecting a tag
  rather than the test initially selects zero cases; it is not acceptance evidence.
- A scoped live attempt reaches provisioning but tool cleanup fails. Safe status
  capture confirms HTTP 409 after agent deletion. The documented force option
  removes dependencies for IDs owned by this operation; its local regression
  fails before implementation, seed 935540.
- Live forced deletion returns HTTP 204 despite reference documentation listing
  200. The local 204 case fails before accepting both confirmed success statuses,
  seed 709087. Error/unsafe/duplicate paths remain failing outcomes.
- Final combined codec/socket/API/group/lease/application checks pass 49/49,
  including real loopback HTTP, seed 676368. These checks use synthetic credentials.
- One selected live create/attach/read/delete case passes in 4.4 seconds,
  seed 103331. No conversation socket, audio or LLM request is made. The fixed
  backend/voice definition is reused; previously passing speech calls are not repeated.

## Failed live cleanup and recovery

Two live attempts created tools whose ordinary deletion returned 409. They left
unused protocol resources; this was not treated as successful cleanup. A bounded
provider query verified two creator-owned client tools with the reserved test
name, exact synthetic description/enum and zero tool calls. Forced deletion
returned 204; the first recovery assertion expected 200 and stopped after one
successful deletion. The corrected recovery verified the remaining resource,
retired it and read the provider again to prove no matching residues remain.
Only boolean/count/status evidence was printed. The temporary recovery probe is
removed; no keys, signed URLs, provider IDs, creator details or env contents enter
committed artifacts. This controlled test recovery is not a general durable journal.

## Completion gates and remaining work

Before the access change, format, warnings-as-errors compile, strict Credo
(1,168 files, no issues) and unused dependencies pass. The default seed-149103
suite reports passing MCP/providers/AgentRuntime checks before stopping in
CallEngine without a terminal result. Its process handle is missing and process
inspection finds no surviving VM. Its termination cause is not established.
A new invocation fails before tests because Mix.PubSub cannot open a TCP socket
in the current sandbox (`:eperm`). A later format check still passes. Do not
claim default-suite acceptance or retry a missing handle as though it were live.

This changes resource ownership, not a speech/source state machine; the eventual
room STS still needs root/Lean/browser acceptance. No frontend files change.
Call-spec schema/prompt translation, native session authority, room tools/credit,
interruption/history/usage, scoped publication, conversational STT and final
milestone acceptance remain open. Review changed documentation and exact diff
before the authorized commit/push; record any permission limitation explicitly.

The continuation reviewed the resource source, focused tests and documentation
diffs. Agent HTTP 204 wording now distinguishes tool retirement's accepted
200/204 statuses. The index records the local/live tool evidence and unresolved
default-suite gate. A new focused Mix invocation still fails at PubSub TCP
startup before tests. The current environment declares the Git metadata directory
read-only and permits no escalation; staging/commit/push has not been attempted
under that restriction. The checkpoint remains uncommitted. A subsequent native
VAD preparation is recorded separately and does not change this tool evidence.
