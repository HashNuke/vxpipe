defmodule Vxpipe.CallEngine.TelemetryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.Provider.{MorseCodeSTT, MorseCodeTTS}

  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]
  @runtime_sample_event [:vxpipe, :call_engine, :runtime, :sample]
  @tts_first_audio_event [:vxpipe, :call_engine, :tts, :first_audio]

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

  test "reports both local Morse speech implementations as one bounded provider" do
    handler_id = {__MODULE__, self(), make_ref()}

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               [@tts_first_audio_event, @provider_failure_event],
               &__MODULE__.handle_event/4,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    started_at = Telemetry.started_at()
    assert :ok = Telemetry.tts_first_audio(started_at, MorseCodeTTS)

    assert_receive {:embedded_telemetry, @tts_first_audio_event, %{duration: duration},
                    %{provider: :morse}}

    assert is_integer(duration) and duration >= 0

    assert :ok = Telemetry.provider_failure(:stt, MorseCodeSTT, :provider_failed)

    assert_receive {:embedded_telemetry, @provider_failure_event, %{count: 1},
                    %{capability: :stt, provider: :morse, category: :unavailable}}
  end

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:embedded_telemetry, event, measurements, metadata})
  end
end
