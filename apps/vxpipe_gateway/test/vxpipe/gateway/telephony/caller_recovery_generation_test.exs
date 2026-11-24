defmodule Vxpipe.Gateway.Telephony.CallerRecoveryGenerationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Media.Registry, as: MediaRegistry
  alias Vxpipe.Gateway.Telephony.CallerRecovery

  test "a new registered session must establish its own recovery eligibility" do
    connection = "generation-test-#{System.unique_integer([:positive])}"
    key = {:telephony_media_session, connection}
    binding = %{caller_recovery?: true, client_state_leg_id: connection}
    state = %{incoming_identity: %{binding: binding}, caller_media: nil, caller_stream: nil}

    start = %Event{
      kind: :media_started,
      provider: :telnyx,
      provider_call_control_id: "test",
      stream_id: "first-stream"
    }

    first =
      start_supervised!({Agent, fn -> Registry.register(MediaRegistry, key, nil) end}, id: :first)

    state = CallerRecovery.watch_media(state, start, self())
    assert {^first, original_monitor, false} = state.caller_media

    assert {:continue, state} =
             CallerRecovery.handle_info({:caller_media_eligible, first, true}, state)

    Agent.get(first, fn _ -> Registry.unregister(MediaRegistry, key) end)

    second =
      start_supervised!({Agent, fn -> Registry.register(MediaRegistry, key, nil) end},
        id: :second
      )

    start = %{start | stream_id: "second-stream"}
    state = CallerRecovery.watch_media(state, start, self())

    assert :unhandled =
             CallerRecovery.handle_info({:caller_stream_stopped, self(), "first-stream"}, state)

    assert {^second, new_monitor, false} = state.caller_media
    refute original_monitor == new_monitor
    assert :unhandled = CallerRecovery.handle_info({:caller_media_eligible, first, true}, state)

    assert :unhandled =
             CallerRecovery.handle_info(
               {:DOWN, original_monitor, :process, first, :killed},
               state
             )

    assert {:continue, state} =
             CallerRecovery.handle_info({:caller_media_eligible, second, true}, state)

    assert {^second, ^new_monitor, true} = state.caller_media
    assert CallerRecovery.watch_media(state, start, self()) == state
  end
end
