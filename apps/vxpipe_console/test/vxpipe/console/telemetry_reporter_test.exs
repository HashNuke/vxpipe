defmodule Vxpipe.Console.TelemetryReporterTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.TelemetryReporter

  @gateway_request_stop [:vxpipe, :gateway, :http, :request, :stop]
  @model_first_token [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop [:vxpipe, :call_engine, :model, :request, :stop]
  @tts_first_audio [:vxpipe, :call_engine, :tts, :first_audio]
  @provider_failure [:vxpipe, :call_engine, :provider, :failure]
  @runtime_sample [:vxpipe, :call_engine, :runtime, :sample]

  test "projects safe bounded aggregates and current runtime health" do
    {_child_id, reporter} = start_reporter(max_pending_events: 32)
    sentinel = "must-not-enter-reporter-state"

    :telemetry.execute(
      @gateway_request_stop,
      %{duration: duration_ms(12), private_value: sentinel},
      %{operation: :health_check, outcome: :ok, status: 200, request_id: sentinel}
    )

    :telemetry.execute(
      @model_first_token,
      %{duration: duration_ms(20)},
      %{provider: :req_llm, output: sentinel}
    )

    :telemetry.execute(
      @model_request_stop,
      %{duration: duration_ms(35)},
      %{provider: :req_llm, outcome: :unavailable, first_output: :missing}
    )

    :telemetry.execute(
      @tts_first_audio,
      %{duration: duration_ms(9)},
      %{provider: :deepgram}
    )

    :telemetry.execute(
      @provider_failure,
      %{count: 1},
      %{capability: :model, provider: :req_llm, category: :unavailable, error: sentinel}
    )

    :telemetry.execute(
      @runtime_sample,
      %{active_rooms: 2, memory_bytes: 123_456, run_queue: 1},
      %{node: sentinel}
    )

    snapshot = TelemetryReporter.snapshot(reporter)

    assert snapshot.received_events == 6
    assert snapshot.dropped_events == 0
    assert is_integer(snapshot.last_event_age_ms) and snapshot.last_event_age_ms >= 0

    assert snapshot.http.requests[{:health_check, :ok}] == duration_stats(12_000)
    assert snapshot.model.first_token[:req_llm] == duration_stats(20_000)
    assert snapshot.model.requests[{:req_llm, :unavailable, :missing}] == 1
    assert snapshot.tts.first_audio[:deepgram] == duration_stats(9_000)
    assert snapshot.provider_failures[{:model, :req_llm, :unavailable}] == 1

    assert %{active_rooms: 2, memory_bytes: 123_456, run_queue: 1, age_ms: age_ms} =
             snapshot.runtime

    assert is_integer(age_ms) and age_ms >= 0
    refute inspect(snapshot) =~ sentinel
  end

  test "drops excess pending events instead of growing its mailbox" do
    {_child_id, reporter} = start_reporter(max_pending_events: 2)
    :ok = :sys.suspend(reporter)

    Enum.each(1..5, fn active_rooms ->
      :telemetry.execute(
        @runtime_sample,
        %{active_rooms: active_rooms, memory_bytes: 100, run_queue: 0},
        %{}
      )
    end)

    :ok = :sys.resume(reporter)
    snapshot = TelemetryReporter.snapshot(reporter)

    assert snapshot.received_events == 2
    assert snapshot.dropped_events == 3
    assert snapshot.runtime.active_rooms == 2
  end

  test "keeps the local diagnostic fixture as a bounded provider dimension" do
    {_child_id, reporter} = start_reporter(max_pending_events: 4)

    :telemetry.execute(
      @model_request_stop,
      %{duration: duration_ms(2)},
      %{provider: :local_fixture, outcome: :unavailable, first_output: :missing}
    )

    assert TelemetryReporter.snapshot(reporter).model.requests[
             {:local_fixture, :unavailable, :missing}
           ] == 1
  end

  test "sanitizes queued events and never dimensions aggregates by call identity" do
    {_child_id, reporter} = start_reporter(max_pending_events: 128)
    sentinel = "private-sentinel"
    :ok = :sys.suspend(reporter)

    Enum.each(1..100, fn sequence ->
      :telemetry.execute(
        @model_request_stop,
        %{duration: duration_ms(2), text: "#{sentinel}-text-#{sequence}"},
        %{
          provider: "#{sentinel}-provider-#{sequence}",
          outcome: :ok,
          first_output: :observed,
          call_id: "#{sentinel}-call-#{sequence}",
          participant_id: "#{sentinel}-participant-#{sequence}",
          turn_id: "#{sentinel}-turn-#{sequence}",
          variables: %{"private" => "#{sentinel}-variable-#{sequence}"}
        }
      )
    end)

    assert {:messages, queued_messages} = Process.info(reporter, :messages)
    refute inspect(queued_messages) =~ sentinel

    :ok = :sys.resume(reporter)
    snapshot = TelemetryReporter.snapshot(reporter)

    assert snapshot.received_events == 100
    assert snapshot.model.requests == %{{:other, :ok, :observed} => 100}
    refute inspect(snapshot) =~ sentinel
  end

  test "replaces a stale handler after an abrupt stop and detaches on normal shutdown" do
    handler_id = {__MODULE__, make_ref()}
    {_first_child_id, first} = start_reporter(handler_id: handler_id)
    first_monitor = Process.monitor(first)

    Process.exit(first, :kill)
    assert_receive {:DOWN, ^first_monitor, :process, ^first, :killed}

    {second_child_id, second} = start_reporter(handler_id: handler_id)

    assert handler_count(handler_id) == 1

    :telemetry.execute(
      @runtime_sample,
      %{active_rooms: 0, memory_bytes: 100, run_queue: 0},
      %{}
    )

    assert TelemetryReporter.snapshot(second).received_events == 1

    second_monitor = Process.monitor(second)
    assert :ok = stop_supervised(second_child_id)
    assert_receive {:DOWN, ^second_monitor, :process, ^second, :shutdown}
    assert handler_count(handler_id) == 0
  end

  defp start_reporter(overrides) do
    child_id = {TelemetryReporter, make_ref()}

    options =
      Keyword.merge(
        [
          name: nil,
          handler_id: {__MODULE__, make_ref()},
          max_pending_events: 16
        ],
        overrides
      )

    reporter =
      start_supervised!(
        Supervisor.child_spec({TelemetryReporter, options}, id: child_id, restart: :temporary)
      )

    {child_id, reporter}
  end

  defp duration_ms(milliseconds) do
    System.convert_time_unit(milliseconds, :millisecond, :native)
  end

  defp duration_stats(microseconds) do
    %{
      count: 1,
      total_us: microseconds,
      minimum_us: microseconds,
      maximum_us: microseconds,
      latest_us: microseconds
    }
  end

  defp handler_count(handler_id) do
    @runtime_sample
    |> :telemetry.list_handlers()
    |> Enum.count(fn handler -> handler.id == handler_id end)
  end
end
