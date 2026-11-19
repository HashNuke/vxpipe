defmodule Vxpipe.CallEngine.RoomAuthority.DiagnosticNotificationsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.{RoomAuthority, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Diagnostics.RoomService

  setup do
    incarnation = "diagnostic-" <> Integer.to_string(System.unique_integer([:positive]))

    snapshot = %Snapshot{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: incarnation,
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "command"
    }

    supervisor = start_supervised!({RoomCapabilitySupervisor, incarnation_id: incarnation})
    {:ok, capability} = DynamicSupervisor.start_child(supervisor, {Agent, fn -> :source end})
    {:ok, ingress} = DynamicSupervisor.start_child(supervisor, {Agent, fn -> :ingress end})
    cap_ref = Process.monitor(capability)
    ingress_ref = Process.monitor(ingress)
    state = State.new(%Recorder{port: nil, participant_activations: %{}}, snapshot, %{})

    connection = %{
      pid: self(),
      participant_id: "human",
      speech_to_text: %{
        capability: capability,
        ingress: ingress,
        capability_monitor: cap_ref,
        ingress_monitor: ingress_ref
      }
    }

    state = %{
      state
      | connections: %{"connection" => connection},
        speech_to_text_monitors: %{cap_ref => "connection", ingress_ref => "connection"}
    }

    identity = %{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: incarnation,
      participant_id: "human",
      connection_id: "connection"
    }

    %{state: state, identity: identity, capability: capability}
  end

  @tag timeout: 2_000
  test "accepted STT loss notifies only its room without waiting for diagnostics", c do
    parent = self()
    {:via, Registry, {registry, key}} = RoomService.address(c.identity)

    receiver =
      start_supervised!(
        {Task,
         fn ->
           {:ok, _} = Registry.register(registry, key, nil)
           send(parent, :registered)

           receive do
             :release -> :ok
           end
         end}
      )

    assert_receive :registered

    assert {:noreply, state} =
             RoomAuthority.handle_info(
               {:vxpipe_stt_unavailable, c.capability, c.identity, :closed},
               c.state
             )

    assert state.connections["connection"].speech_to_text == nil
    assert {:messages, [{:"$gen_cast", :reconcile}]} = Process.info(receiver, :messages)
  end

  test "missing diagnostics cannot prevent accepted STT cleanup", c do
    assert {:noreply, state} =
             RoomAuthority.handle_info(
               {:vxpipe_stt_unavailable, c.capability, c.identity, :closed},
               c.state
             )

    assert state.connections["connection"].speech_to_text == nil
  end
end
