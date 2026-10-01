defmodule Vxpipe.CallEngine.DirectLLMRoomTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    TestCallStartup,
    TestTenantCredentialSource,
    TestTransferConnection,
    TestTurnCall
  }

  alias Vxpipe.CallEngine.Command.AttachConnection

  for {provider, model} <- [
        {"deepseek", "deepseek-flash"},
        {"openrouter", "google/gemini-3.5-flash-lite"},
        {"fireworks", "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b"}
      ] do
    @tag selection: %{provider: provider, model: model, credential_name: "room-model"}
    test "#{provider} scoped selection starts a compiled room before caller input", %{
      selection: selection
    } do
      source = TestTurnCall.call_spec()

      participants =
        Map.update!(source.participants, "receiver", fn receiver ->
          %{receiver | capabilities: %{model_inference: selection}}
        end)

      assert {:ok, spec} =
               CallSpec.new(%{source | participants: participants},
                 resource_id: "direct-model-room",
                 revision: 1
               )

      assert {:ok, invocation} =
               CallInvocation.new(
                 %{
                   call_spec: %{id: "direct-model-room", revision: 1},
                   transport: %{type: "web"}
                 },
                 tenant_id: "direct-model-room-test",
                 actor_id: "direct-model-room-test"
               )

      assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

      bindings = %{
        {plan.tenant_id, selection.provider, "room-model"} => %{
          "api_key" => "synthetic-direct-room"
        }
      }

      assert {:ok, room} =
               TestCallStartup.start_call(plan,
                 credential_source: {TestTenantCredentialSource, {self(), bindings}}
               )

      tenant = plan.tenant_id
      provider = selection.provider
      assert_receive {:tenant_credential_resolved, ^tenant, ^provider, "room-model"}, 2_000

      [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {tenant, plan.room_id})

      on_exit(fn ->
        try do
          GenServer.stop(authority, :shutdown)
        catch
          :exit, {:noproc, _call} -> :ok
        end
      end)

      caller = Map.fetch!(plan.participants, plan.entry_caller)

      assert {:ok, command} =
               AttachConnection.new(
                 tenant_id: tenant,
                 actor_id: plan.actor_id,
                 room_id: plan.room_id,
                 incarnation_id: room.incarnation_id,
                 participant_id: caller.participant_id,
                 connection_id: "direct-model-caller",
                 deadline: DateTime.add(DateTime.utc_now(), 5, :second)
               )

      assert {:ok, _attachment} = TestTransferConnection.attach(command, nil)
      assert :ok = TestCallStartup.await_ready(plan.room_id)
      assert :open = CallEngine.RoomAuthority.input_admission(tenant, plan.room_id)
      receiver = Map.fetch!(plan.participants, plan.entry_receiver)

      assert {:ok, %{state: :joined}} =
               CallEngine.participant_snapshot(tenant, plan.room_id, receiver.participant_id)
    end
  end
end
