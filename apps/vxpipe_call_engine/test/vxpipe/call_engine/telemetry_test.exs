defmodule Vxpipe.CallEngine.TelemetryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telemetry

  @runtime_sample_event [:vxpipe, :call_engine, :runtime, :sample]

  test "an embedded host can attach to the complete engine event contract" do
    assert Telemetry.events() == [
             [:vxpipe, :call_engine, :model, :first_token],
             [:vxpipe, :call_engine, :model, :request, :stop],
             [:vxpipe, :call_engine, :tts, :first_audio],
             [:vxpipe, :call_engine, :provider, :failure],
             @runtime_sample_event
           ]

    handler_id = {__MODULE__, self(), make_ref()}

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               Telemetry.events(),
               &__MODULE__.handle_event/4,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    measurements = %{active_rooms: 1, memory_bytes: 1_024, run_queue: 0}
    assert :ok = Telemetry.runtime_sample(measurements)

    assert_receive {:embedded_telemetry, @runtime_sample_event, ^measurements, %{}}
  end

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:embedded_telemetry, event, measurements, metadata})
  end
end
