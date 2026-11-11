defmodule Vxpipe.CallEngine.TestCallStartup do
  @moduledoc "Test-owned room startup, teardown and preparation acknowledgements."

  import ExUnit.Assertions
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.RoomAuthority

  def start_call(plan, options \\ []) do
    with {:ok, room} <- CallEngine.start_call(plan, options) do
      stop_on_exit(plan, room)
      await_prepared(plan)
      {:ok, room}
    end
  end

  defp stop_on_exit(plan, room) do
    key = {:room_incarnation, plan.tenant_id, plan.room_id, room.incarnation_id}

    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, key) do
      [{pid, _}] ->
        ExUnit.Callbacks.on_exit(fn ->
          # The test may already have ended this room. Retain the PID rather
          # than looking up an ID that a later incarnation could reuse.
          result = DynamicSupervisor.terminate_child(Vxpipe.CallEngine.RoomSupervisor, pid)
          assert result in [:ok, {:error, :not_found}]
        end)

      [] ->
        :ok
    end
  end

  def await_ready(room_id) when is_binary(room_id) do
    assert_receive {:test_call_ready, ^room_id}, 2_000
    :ok
  end

  def await_ready(%{room_monitor: monitor}) do
    assert_receive {:vxpipe_call_ready, ^monitor}, 2_000
    :ok
  end

  def await_open(plan) do
    await_open(plan, System.monotonic_time(:millisecond) + 2_000)
  end

  defp await_open(plan, deadline) do
    case RoomAuthority.input_admission(plan.tenant_id, plan.room_id) do
      :open ->
        :ok

      :opening_audio ->
        assert System.monotonic_time(:millisecond) < deadline, "call startup did not finish"

        receive do
        after
          5 -> await_open(plan, deadline)
        end
    end
  end

  def await_prepared(plan), do: await_entries(plan, System.monotonic_time(:millisecond) + 2_000)

  defp await_entries(plan, deadline) do
    case RoomAuthority.readiness_binding(room_authority(plan)) do
      {:ok, _binding} ->
        :ok

      {:error, :startup_preparing} ->
        assert System.monotonic_time(:millisecond) < deadline, "entry preparation did not finish"

        receive do
        after
          5 -> await_entries(plan, deadline)
        end
    end
  end

  defp room_authority(plan) do
    [{authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    authority
  end
end
