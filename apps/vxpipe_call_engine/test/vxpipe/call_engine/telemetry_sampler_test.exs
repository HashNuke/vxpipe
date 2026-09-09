defmodule Vxpipe.CallEngine.TelemetrySamplerTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.TelemetrySampler

  @runtime_sample_event [:vxpipe, :call_engine, :runtime, :sample]

  test "samples VM health and the active room supervisor without identifiers" do
    attach_runtime_events()
    room_supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    sampler =
      start_supervised!(
        {TelemetrySampler,
         name: nil, room_supervisor: room_supervisor, sample_interval_ms: 60_000}
      )

    assert %{active_rooms: 0} = first = TelemetrySampler.sample(sampler)
    assert_runtime_event(first)

    assert {:ok, _room} =
             DynamicSupervisor.start_child(
               room_supervisor,
               {Task,
                fn ->
                  receive do
                    :stop -> :ok
                  end
                end}
             )

    assert %{active_rooms: 1} = second = TelemetrySampler.sample(sampler)
    assert_runtime_event(second)
  end

  test "the call-engine application supervises exactly one named sampler" do
    assert is_pid(Process.whereis(TelemetrySampler))

    assert 1 ==
             Supervisor.which_children(Vxpipe.CallEngine.Supervisor)
             |> Enum.count(fn {_id, _pid, _type, modules} -> modules == [TelemetrySampler] end)
  end

  def handle_telemetry_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp attach_runtime_events do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        @runtime_sample_event,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_runtime_event(measurements) do
    assert_receive {:telemetry_event, @runtime_sample_event, ^measurements, %{}}
    assert Map.keys(measurements) |> Enum.sort() == [:active_rooms, :memory_bytes, :run_queue]
    assert measurements.memory_bytes > 0
    assert measurements.run_queue >= 0
  end
end
