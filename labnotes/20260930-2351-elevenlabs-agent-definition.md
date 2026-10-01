# ElevenLabs agent definition investigation

## Intent and rejected integration path

The initial hosted-agent approach investigated preparing one private agent from
Vxpipe's resolved prompt and tool schemas for each call. A static reusable vendor
agent would not satisfy the user's requirement to supply each call's tools.
This was preparation research; no room consumer or provider capability was added.

On 2026-10-01 the user limited ElevenLabs to realtime STT and TTS if hosted agents
could not fit the existing Gemini/OpenAI STS contracts. Output/history and
interruption fit had not been established. The uncommitted agent-definition
builder and its tests were therefore removed rather than extending the shared
STS contracts to accommodate the hosted service. Previously committed native
agent protocol and agent-only resource ownership remain historical research.

## Prototype and test evidence (withdrawn source)

The prototype used a closed bounded configuration, explicit voice/model settings,
private inspection, unmodified caller JSON schemas and response-bearing client
tools. Local schema preflight rejected remote references and vendor controls;
ordinary property names remained possible. It did not resolve actual room tools,
create a room session, or establish provider history/interruption semantics.

Seven initial focused tests failed because the builder was absent. The first
implementation left one schema-shape case failing; a required-list guard made
all seven pass, seed 391736. This direct source ExUnit lane used synthetic data
and no provider connection. A direct static Credo invocation passed 1,169 files
with no issues; this did not replace a Mix compilation or umbrella gate.

The next per-call activation/lease tests were red: nine tests, two failures.
The activation constructor was absent and the existing lease did not accept the
prepared struct. The run completed with exit status 2. No per-call consumer or
lease integration was implemented before the user's scope correction. Those
unfinished tests and the prototype were removed with the STS-only work.

No paid request was made for this prototype. The earlier selected tool-resource
metadata case is recorded separately in the tool-resource investigation.

## Verification and barriers

Cleanup restores only reviewed agent API/lease/request and existing test content
from HEAD and deletes only newly created untracked STS files. Scribe manual/VAD
protocol work remains. Milestone, index, design and live-test documentation now
require ElevenLabs realtime STT/TTS only. Existing commits and unrelated user
content configuration are preserved.

Current sandbox TCP restrictions block Mix.PubSub and live/umbrella execution;
Git metadata is declared read-only with no escalation. No staging, commit or
push is attempted. Offline current-source Scribe tests, format, diff and local
documentation checks provide proportionate cleanup evidence; they do not prove
conversational STT admission or final milestone acceptance.

## Scope-cleanup verification

After removing the new STS-only work, the current-source Scribe lane passes nine
tests, zero failures, seed 673268. Root format verification passes. Direct static
Credo passes 1,167 source files and 38 checks with no issues; this remains separate
from the unavailable Mix gates. All 174 local Markdown targets in changed docs
and investigation labnotes exist, and documented Scribe/manual/VAD and historical
agent test line selections point at actual tests. Git diff whitespace checks
pass; the three committed agent lifecycle modules match HEAD byte-for-byte and
the index remains empty. The unrelated user content configuration retains its
original checksum. No API request is made. Pushnotify sends the scope/progress
update.
