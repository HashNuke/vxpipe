# WebRTC source arm

Objective: implement the first Gateway caller-boundary slice of the existing
STS native source-time hold/reopen gate. This is not room-coordinated admission.

`RoomSupervisor.attach_connection/2` already returns the owning RoomAuthority
PID, and the RoomAuthority connection record retains the same private
`room_monitor` reference returned to Gateway. `CallEngine.attach_connection/2`
now carries that PID in the internal `ConnectionAttachment`. Gateway checks
both PID and monitor for a main attachment before accepting a source command.
The room must eventually send these commands from its own PID through a
correlated asynchronous request; no room caller is wired in this checkpoint.

Red: the new focused Gateway test initially could not construct the attachment
because it lacked `room_authority`. After adding that private field, it failed
with `FunctionClauseError` for the missing Connection hold/arm callbacks (two
tests, two failures). The implementation added `Connection.SourceCutover` and
the independent `SourceAudio` gate. Hold closes the Connection source gate
before asking the receiver to rotate old→held. Arm validates the exact
receipt/token/attachment and transfer gate, rotates held→active, updates
Connection's expected epoch, and opens its local gate within one blocked
callback. The receiver's fixed peer call is covered by an eight-second maximum
operation budget, with absolute expiry checked before and after cutover.
Ambiguous receiver results terminalize the token and leave local admission
closed. The room must keep its own ingress closed on an ambiguous arm reply.

Further controlled reds found three replay errors in the first implementation:
the same token could start a second hold, a transfer-blocked arm could be
retried after transfer release, and an expired arm could be retried with a new
deadline. All now fail closed and terminalize valid failed arm attempts. A
separate red showed that arming back to the pre-hold epoch was accepted; it is
now rejected so old stamped RTP cannot match the active epoch.

Focused tests cover authorization and wrong attachment, old/held/active RTP,
late peer acknowledgement, receiver loss, stale/wrong receipts, terminal
expiry, transfer overlap and the SourceAudio hold gate. The Gateway
`connection_source_cutover_test.exs`, `source_receiver_test.exs`, and
`sts_input_test.exs` group passes 23/0 on seeds 0 and 1. The Call Engine
`text_turn_test.exs` attachment case passes 4/0. Independent review and
post-commit umbrella gates remain pending. No hosted provider was called.

Continuation: RoomAuthority now sends correlated asynchronous source hold/arm
requests and selected STT ingress closes on origin replacement; see
[`20260924-0219-room-sts-source-cutover.md`](20260924-0219-room-sts-source-cutover.md).
Native STT retirement/fresh-generation room acceptance, transfer/policy overlap,
transcription-only recovery, telephony raw callback cutover, and full
room/native acceptance remain open. This Gateway boundary slice alone does not
close the B room/native task.

Current-worktree verification: the 23-test Gateway source-receiver/cutover/STS
input group passes on seeds 0 and 1; the four-test Call Engine attachment file
passes on seeds 0 and 1. Changed Elixir files pass exact-path format checking;
umbrella warnings-as-errors compile, strict Credo (1,103 source files, no
issues), unused-dependency check, and `git diff --check` pass. The full umbrella
suite and independent implementation review were not run for this focused
checkpoint. An umbrella-root path invocation stopped during Persistence repo
startup because the local PostgreSQL password is unconfigured; the owning-child
test commands above were rerun and passed. Room coordination and the milestone's
final acceptance remain open.
