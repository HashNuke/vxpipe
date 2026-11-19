# Idle admission after silent acknowledgment

Status: reproduced, unresolved; discovered during passive-diagnostics root checks
on 2026-11-19. This is an existing idle-tool ordering issue, not a diagnostics
capture dependency. The expiry-test synchronization change does not fix it.

The asynchronous idle invocation can reach the room after a silent acknowledgment
has completed. Completion deletes the origin turn; `IdleWait.authorize/2` then
rejects the otherwise-current invocation because that origin is absent. The
requested hold is never established. Messages originate in separate processes,
so their relative delivery order is not guaranteed.

## Evidence and reproduction

The full suite at diagnostic projection checkpoint reported nil `idle_wait` in
`IdleRoomTest`'s manually triggered expiry case (seed 52109). The focused test
passes alone. That failure cannot identify whether delayed admission or its
competing one-second timer occurred. Independent Astra review reproduced delayed
admission using a 300-second duration, ruling out the short timer for that case.

Insert this temporary test inside
`apps/vxpipe_call_engine/test/vxpipe/call_engine/agent_runtime/idle_room_test.exs`
to reuse its existing fixtures, then run from the Engine child:

```sh
mix test test/vxpipe/call_engine/agent_runtime/idle_room_test.exs --only idle_admission_race --seed 52109
```

```elixir
@tag :idle_admission_race
test "delayed idle admission still establishes the requested hold" do
  {_plan, room, caller, _voice, _sink} = start_call()
  submit(room, caller, "Wait", "late-idle")
  [{room_pid, _}] = Registry.lookup(CallEngine.RoomRegistry, {room.tenant_id, room.room_id})
  :ok = :sys.suspend(room_pid)

  on_exit(fn ->
    try do
      :sys.resume(room_pid)
    catch
      :exit, _ -> :ok
    end
  end)

  {acknowledgment, _request} = invoke_idle(300)
  parent = self()

  # Delay delivery of the original Task request; leave room state unchanged.
  :sys.replace_state(room_pid, fn state ->
    receive do
      {:"$gen_call", _from, {:idle, _request}} = call -> send(parent, {:held_idle, call})
    after
      1_000 -> flunk("Idle request was not sent")
    end

    state
  end)

  assert_receive {:held_idle, call}
  reply(acknowledgment, :listener, nil)
  :ok = :sys.resume(room_pid)
  assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "late-idle"}}
  send(room_pid, call)
  assert %{phase: :quiet} = :sys.get_state(room_pid).idle_wait
end
```

Expected: a quiet hold. Actual: nil; one failing assertion. The controlled mailbox
delivery represents a permissible cross-sender ordering without changing room
state or the original caller identity. Remove the temporary test after reproducing
until implementing the fix; it is intentionally failing evidence, not a passing gate.

## Resolution constraints

Establish ordering between successful idle admission and acknowledgment completion,
or retain narrowly scoped origin authority until admission settles. Do not accept
stale invocations after new human input, cancellation, source replacement or
participant departure. Add the reproduction as a retained red/green regression
when implementing the runtime fix; retain existing timed-expiry and completion
ordering coverage. Changes to the production state machine require Lean checks.
