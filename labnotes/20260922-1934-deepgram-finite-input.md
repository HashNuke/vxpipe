# Deepgram finite input

2026-09-22 research checkpoint. Starting branch `sts-output-recognition-20260922`
at `aa67912c523601133d8f4c7a0ddd5f3912ed739f`; `git status --short --branch`
was clean before `bin/create-labnotes deepgram-finite-input`. Previous finite
recognition/deadline checkpoints are unchanged. No other worktree was modified.

Read AGENTS, milestone index/current D tasks, finite settlement decision and
provider finite-input contract, existing Deepgram Flux/session/socket and shared
socket receive/close paths. Added finer protocol-proof/transport/test tasks and
separate design review before any runtime/test edits. See
[the decision, exact source pins and proposed seam](../docs/deepgram-finite-input-proof.md).

## Methods and outcome

Public read-only browser requests covered official Deepgram Flux CloseStream,
ForceEndTurn, Flux API, Nova CloseStream/Finalize, and Google's current Live
Transcribe guide. No SDK examples/live tests were executed. No credentials were
read and no upstream messages or billable requests were sent.

Pinned public-source inspection used `curl -fsSL` to stdout, not a checkout or
build. Commit metadata selected these public source pins:

```sh
curl -fsSL https://api.github.com/repos/deepgram/deepgram-dotnet-sdk/commits/main | jq '{sha:.sha,date:.commit.committer.date}'
curl -fsSL https://raw.githubusercontent.com/deepgram/deepgram-dotnet-sdk/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram/Clients/Flux/WebSocket/Client.cs | nl -ba | sed -n '350,510p'
curl -fsSL https://raw.githubusercontent.com/deepgram/deepgram-dotnet-sdk/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram.Tests/Fixtures/Flux/frames.json | jq '{description,url,close}'
curl -fsSL https://raw.githubusercontent.com/deepgram/deepgram-dotnet-sdk/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram.Tests/UnitTests/ClientTests/FluxParityTests.cs | nl -ba | sed -n '1,230p'
curl -fsSL https://raw.githubusercontent.com/deepgram/deepgram-dotnet-sdk/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram.Tests/UnitTests/ClientTests/FluxLiveIntegrationTests.cs | nl -ba | sed -n '1,260p'
curl -fsSL https://raw.githubusercontent.com/deepgram/deepgram-api-specs/6668bc2d5c3dc720697364f8c2ce3c8c0e27fbc5/asyncapi.yml | nl -ba | sed -n '204,223p'
```

These are reproduction methods; the moving `main` metadata query need not retain
the recorded result. SDK pin commit date was 2026-09-17T10:37:08Z; specification
pin date was 2026-09-18T10:14:23Z. The pinned URLs reproduce the inspected contents.
Also read the pinned raw WebSocket example and base AbstractWebSocketClient.

The source supports a nominal decode/update/close sequence but does not settle
the exact successful close observable. ForceEndTurn does not decode the buffered
tail. The SDK grace period and Stop fallback are not proof. The fixture's `close`
is an empty object and the parity test consumes only text frames. An initial jq
probe incorrectly assumed the fixture root was an array (exit 5); corrected object
probes completed exit 0. An inventory rg probe included a nonexistent Deepgram
top-level filename (exit 2); actual Flux module inspection confirms only Flux
models. Neither diagnostic error was a runtime red or protocol experiment.

Current Socket close initiates local teardown; current disconnect erases peer
close distinctions. Proposed shared opt-in close-evidence seam requires parent
coordination, not an out-of-scope edit. Empty close frame and EOF are not synonymous;
we do not infer either from missing status alone. No finite capability flag change
or unsupported fallback has been implemented. Existing Google STT and local Morse
alternatives are explicitly assessed; Nova Metadata is promising but outside the
current supported model/endpoint set. Hosted requirement stays unchecked.

## Verification / handles

Documentation-only research: no RGR claim, no compile/tests, no new test log or
BEAM session. Every read-only command completed; none returned a live session ID.
In particular source probes `64963b`, `d3bc9e`, `259533`, and `c8c0cd` exited 0.
No root/native/load/hosted acceptance was run. Runtime remains exactly the prior
reviewed checkpoint. `git diff --check` and `git diff --cached --check` passed
(handles `13239d` and `6ce9a7`, exit 0). Checked the relative local document targets
exist and are nonempty (`b6e839`, exit 0), and reviewed the exact three-path staged
diff. No source, fixture, dependency, manifest or index acceptance change is staged.
Implementation and its red/green evidence remain pending protocol/scope resolution.
