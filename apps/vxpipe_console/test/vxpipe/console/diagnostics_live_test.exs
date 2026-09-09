defmodule Vxpipe.Console.DiagnosticsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Vxpipe.Console.TelemetryReporter

  @endpoint Vxpipe.Console.Endpoint
  @gateway_request_stop [:vxpipe, :gateway, :http, :request, :stop]
  @model_first_token [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop [:vxpipe, :call_engine, :model, :request, :stop]
  @tts_first_audio [:vxpipe, :call_engine, :tts, :first_audio]
  @provider_failure [:vxpipe, :call_engine, :provider, :failure]
  @runtime_sample [:vxpipe, :call_engine, :runtime, :sample]

  setup do
    original = Application.fetch_env!(:vxpipe_console, :diagnostics)

    Application.put_env(
      :vxpipe_console,
      :diagnostics,
      original
      |> Keyword.put(:enabled, true)
      |> Keyword.put(:reporter, TelemetryReporter)
    )

    on_exit(fn -> Application.put_env(:vxpipe_console, :diagnostics, original) end)
  end

  test "renders live bounded call-path measurements" do
    :telemetry.execute(
      @gateway_request_stop,
      %{duration: duration_ms(4)},
      %{operation: :health_check, outcome: :ok, status: 200}
    )

    :telemetry.execute(
      @model_first_token,
      %{duration: duration_ms(15)},
      %{provider: :req_llm}
    )

    :telemetry.execute(
      @model_request_stop,
      %{duration: duration_ms(30)},
      %{provider: :req_llm, outcome: :timeout, first_output: :missing}
    )

    :telemetry.execute(
      @tts_first_audio,
      %{duration: duration_ms(7)},
      %{provider: :deepgram}
    )

    :telemetry.execute(
      @provider_failure,
      %{count: 1},
      %{capability: :model, provider: :req_llm, category: :timeout}
    )

    emit_runtime(7)

    {:ok, view, _html} = live(build_conn(), "/diagnostics")

    assert has_element?(view, "#diagnostics-board")
    assert has_element?(view, "#collection-state", "Collecting")
    assert has_element?(view, ~s([data-metric="active-rooms"]), "7")
    assert has_element?(view, ~s([data-metric="memory"]), "500.0 MiB")
    assert has_element?(view, ~s([data-metric="run-queue"]), "2")
    assert has_element?(view, "#http-health-check-ok", "4.0 ms")
    assert has_element?(view, "#model-first-token-req-llm", "15.0 ms")

    assert has_element?(
             view,
             "#model-request-req-llm-timeout-missing",
             "No first output"
           )

    assert has_element?(view, "#tts-first-audio-deepgram", "7.0 ms")
    assert has_element?(view, "#provider-failure-model-req-llm-timeout", "1")
    assert has_element?(view, ~s(a[href="/diagnostics/system"]), "System dashboard")
    assert has_element?(view, ~s(a[href="/"]), "Voice console")
  end

  test "refreshes the current snapshot without accumulating browser history" do
    emit_runtime(3)
    {:ok, view, _html} = live(build_conn(), "/diagnostics")

    assert has_element?(view, ~s([data-metric="active-rooms"]), "3")

    emit_runtime(8)
    send(view.pid, :refresh)

    assert has_element?(view, ~s([data-metric="active-rooms"]), "8")
  end

  test "shows an honest unavailable state when the reporter cannot be reached" do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    Application.put_env(
      :vxpipe_console,
      :diagnostics,
      Keyword.put(diagnostics, :reporter, :missing_diagnostics_reporter)
    )

    {:ok, view, _html} = live(build_conn(), "/diagnostics")

    assert has_element?(view, "#collection-state", "Collector unavailable")
    assert has_element?(view, "#diagnostics-unavailable", "Call traffic is unaffected")
  end

  defp emit_runtime(active_rooms) do
    :telemetry.execute(
      @runtime_sample,
      %{active_rooms: active_rooms, memory_bytes: 524_288_000, run_queue: 2},
      %{}
    )
  end

  defp duration_ms(milliseconds) do
    System.convert_time_unit(milliseconds, :millisecond, :native)
  end
end
