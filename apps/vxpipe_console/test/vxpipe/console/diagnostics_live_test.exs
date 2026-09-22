defmodule Vxpipe.Console.DiagnosticsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Vxpipe.Console.InstallationOperatorSession
  alias Vxpipe.Console.TelemetryReporter
  alias Vxpipe.CallEngine.Diagnostics.ModelFixture
  alias Vxpipe.Gateway.HTTP.Mount

  @endpoint Vxpipe.Console.Endpoint
  @background_admission [:vxpipe, :call_engine, :background_tool, :admission]
  @background_handoff [:vxpipe, :call_engine, :background_tool, :handoff]
  @background_stop [:vxpipe, :call_engine, :background_tool, :stop]
  @gateway_request_stop [:vxpipe, :gateway, :http, :request, :stop]
  @model_first_token [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop [:vxpipe, :call_engine, :model, :request, :stop]
  @mcp_connection_stop [:vxpipe, :mcp, :connection, :stop]
  @mcp_request_stop [:vxpipe, :mcp, :request, :stop]
  @opening_audio_stop [:vxpipe, :call_engine, :opening_audio, :stop]
  @tts_first_audio [:vxpipe, :call_engine, :tts, :first_audio]
  @provider_failure [:vxpipe, :call_engine, :provider, :failure]
  @runtime_sample [:vxpipe, :call_engine, :runtime, :sample]
  @room_mount_options Mount.init(
                        room_creation: [
                          enabled: true,
                          principal: [
                            tenant_id: "tenant-diagnostics-test",
                            actor_id: "actor-diagnostics-test",
                            scopes: ["rooms:create"]
                          ]
                        ]
                      )

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

  test "loads diagnostics through compiled static assets" do
    html = html_response(get(authenticated_conn(), "/admin/diagnostics"), 200)

    assert html =~ ~s(href="/assets/diagnostics.css")
    assert html =~ ~s(type="module" src="/assets/live.js")
    refute html =~ "/admin/diagnostics/assets/"
    refute html =~ "<style>"
  end

  test "renders live bounded call-path measurements" do
    {_child_id, reporter} = start_reporter({__MODULE__, make_ref()}, 32)
    configure_reporter(reporter)
    sentinel = "private-diagnostics-sentinel"

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
      %{duration: duration_ms(30), text: sentinel},
      %{
        provider: :req_llm,
        outcome: :timeout,
        first_output: :missing,
        call_id: sentinel,
        participant_id: sentinel,
        turn_id: sentinel,
        variables: %{"private" => sentinel}
      }
    )

    :telemetry.execute(
      @tts_first_audio,
      %{duration: duration_ms(7)},
      %{provider: :deepgram}
    )

    :telemetry.execute(
      @opening_audio_stop,
      %{count: 1, duration: duration_ms(6)},
      %{source: :text, outcome: :completed}
    )

    :telemetry.execute(
      @provider_failure,
      %{count: 1},
      %{capability: :model, provider: :req_llm, category: :timeout}
    )

    :telemetry.execute(
      @background_admission,
      %{count: 1, reserved: 1, limit: 4},
      %{outcome: :accepted}
    )

    :telemetry.execute(
      @background_stop,
      %{count: 1, duration: duration_ms(2)},
      %{outcome: :unknown}
    )

    :telemetry.execute(
      @background_handoff,
      %{count: 1, depth: 1, limit: 4},
      %{outcome: :queued}
    )

    :telemetry.execute(
      @mcp_connection_stop,
      %{active_connections: 2, count: 1, duration: duration_ms(5)},
      %{operation: :open, outcome: :opened, client: self(), integration_id: sentinel}
    )

    :telemetry.execute(
      @mcp_request_stop,
      %{count: 1, duration: duration_ms(8), result: sentinel},
      %{operation: :invocation, outcome: :remote_error, client: self(), tool_name: sentinel}
    )

    emit_runtime(7)

    {:ok, view, _html} = live(authenticated_conn(), "/admin/diagnostics")

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
    assert has_element?(view, "#opening-audio-text-completed", "Completed 6.0 ms 1")
    assert has_element?(view, "#provider-failure-model-req-llm-timeout", "1")
    assert has_element?(view, "#background-reservation-pressure", "1 / 4")
    assert has_element?(view, "#background-mailbox-pressure", "1 / 4")
    assert has_element?(view, "#background-admission-accepted td:first-child", "Accepted")
    assert has_element?(view, "#background-admission-accepted td:last-child")
    assert has_element?(view, "#background-worker-unknown td:first-child", "Unknown")
    assert has_element?(view, "#background-worker-unknown td:nth-child(2)", "2.0 ms")
    assert has_element?(view, "#background-worker-unknown td:last-child")
    assert has_element?(view, "#background-handoff-queued td:first-child", "Queued")
    assert has_element?(view, "#background-handoff-queued td:last-child")
    assert has_element?(view, "#mcp-active-connections", "2")
    assert has_element?(view, "#mcp-queue-pressure", "Not applicable")
    assert has_element?(view, "#mcp-connection-open-opened td:first-child", "Open")
    assert has_element?(view, "#mcp-connection-open-opened td:nth-child(2)", "Opened")
    assert has_element?(view, "#mcp-connection-open-opened td:nth-child(3)", "5.0 ms")
    assert has_element?(view, "#mcp-connection-open-opened td:last-child", "1")

    assert has_element?(view, "#mcp-request-invocation-remote-error td:first-child", "Invocation")

    assert has_element?(
             view,
             "#mcp-request-invocation-remote-error td:nth-child(2)",
             "Remote error"
           )

    assert has_element?(view, "#mcp-request-invocation-remote-error td:nth-child(3)", "8.0 ms")
    assert has_element?(view, "#mcp-request-invocation-remote-error td:last-child", "1")

    assert has_element?(view, ~s(a[href="/admin/diagnostics/system"]), "System dashboard")
    assert has_element?(view, ~s(a[href="/admin/samples/pipecat-console"]), "Voice console")
    refute render(view) =~ sentinel
  end

  test "refreshes the current snapshot without accumulating browser history" do
    emit_runtime(3)
    {:ok, view, _html} = live(authenticated_conn(), "/admin/diagnostics")

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

    {:ok, view, _html} = live(authenticated_conn(), "/admin/diagnostics")

    assert has_element?(view, "#collection-state", "Collector unavailable")
    assert has_element?(view, "#diagnostics-unavailable", "Call traffic is unaffected")
  end

  test "renders cancelled and unavailable work without inventing first output or audio" do
    reporter =
      start_supervised!(
        {TelemetryReporter,
         name: nil, handler_id: {__MODULE__, make_ref()}, max_pending_events: 16}
      )

    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    Application.put_env(
      :vxpipe_console,
      :diagnostics,
      Keyword.put(diagnostics, :reporter, reporter)
    )

    :telemetry.execute(
      @model_request_stop,
      %{duration: duration_ms(11)},
      %{provider: :req_llm, outcome: :cancelled, first_output: :missing}
    )

    :telemetry.execute(
      @model_request_stop,
      %{duration: duration_ms(12)},
      %{provider: :req_llm, outcome: :unavailable, first_output: :missing}
    )

    :telemetry.execute(
      @provider_failure,
      %{count: 1},
      %{capability: :model, provider: :req_llm, category: :unavailable}
    )

    {:ok, view, _html} = live(authenticated_conn(), "/admin/diagnostics")

    assert has_element?(view, ".empty-state", "No first-output timing observed.")

    assert has_element?(
             view,
             "#model-request-req-llm-cancelled-missing",
             "Cancelled No first output 1"
           )

    assert has_element?(
             view,
             "#model-request-req-llm-unavailable-missing",
             "Unavailable No first output 1"
           )

    assert has_element?(view, ".empty-state", "No synthesized-audio timing observed.")
    assert has_element?(view, "#provider-failure-model-req-llm-unavailable", "1")
  end

  test "call admission survives collector saturation, dashboard disconnect, and restart" do
    handler_id = {__MODULE__, make_ref()}
    {_first_child_id, first_reporter} = start_reporter(handler_id, 1)
    configure_reporter(first_reporter)

    :ok = :sys.suspend(first_reporter)
    assert admit_room("room-collector-suspended").status == 201
    assert health_request().status == 200
    assert health_request().status == 200
    assert health_request().status == 200

    {:ok, first_view, _html} = live(authenticated_conn(), "/admin/diagnostics")
    assert has_element?(first_view, "#collection-state", "Collector unavailable")

    first_view_monitor = Process.monitor(first_view.pid)
    :ok = GenServer.stop(first_view.pid, :normal)
    assert_receive {:DOWN, ^first_view_monitor, :process, _pid, :normal}

    :ok = :sys.resume(first_reporter)

    assert %{received_events: 1, dropped_events: dropped_events} =
             TelemetryReporter.snapshot(first_reporter)

    assert dropped_events >= 3

    received_before_disconnect = TelemetryReporter.snapshot(first_reporter).received_events
    assert health_request().status == 200

    assert TelemetryReporter.snapshot(first_reporter).received_events >=
             received_before_disconnect + 1

    first_reporter_monitor = Process.monitor(first_reporter)
    Process.exit(first_reporter, :kill)
    assert_receive {:DOWN, ^first_reporter_monitor, :process, ^first_reporter, :killed}

    assert admit_room("room-collector-offline").status == 201

    {_second_child_id, second_reporter} = start_reporter(handler_id, 4)
    configure_reporter(second_reporter)

    assert handler_count(handler_id) == 1

    assert %{received_events: 0, dropped_events: 0, last_event_age_ms: nil} =
             TelemetryReporter.snapshot(second_reporter)

    {:ok, second_view, _html} = live(authenticated_conn(), "/admin/diagnostics")
    assert has_element?(second_view, "#collection-state", "Waiting for signals")

    assert health_request().status == 200
    send(second_view.pid, :refresh)

    assert has_element?(second_view, "#collection-state", "Collecting")
    assert TelemetryReporter.snapshot(second_reporter).received_events == 1
  end

  test "opening diagnostics does not create rooms, participants, or call-path observations" do
    {_child_id, reporter} = start_reporter({__MODULE__, make_ref()}, 4)
    configure_reporter(reporter)
    registry_entries_before = registry_entries()
    room_children_before = room_children()

    assert TelemetryReporter.snapshot(reporter).received_events == 0
    {:ok, view, _html} = live(authenticated_conn(), "/admin/diagnostics")
    assert has_element?(view, "#diagnostics-board")

    assert MapSet.subset?(registry_entries(), registry_entries_before)
    assert MapSet.subset?(room_children(), room_children_before)

    assert %{
             received_events: 0,
             model: %{first_token: %{}, requests: %{}},
             provider_failures: %{},
             tts: %{first_audio: %{}}
           } = TelemetryReporter.snapshot(reporter)
  end

  test "arms the next local model outcome when the opt-in fixture is available" do
    fixture =
      start_supervised!(
        {ModelFixture,
         name: nil, default_scenario: :success, delay_ms: 0, response: "Local fixture response."}
      )

    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    Application.put_env(
      :vxpipe_console,
      :diagnostics,
      Keyword.put(diagnostics, :model_fixture, fixture)
    )

    {:ok, view, _html} = live(authenticated_conn(), "/admin/diagnostics")

    assert has_element?(view, "#model-fixture-controls", "Next request: Success")
    assert view |> element(~s(button[phx-value-scenario="failure"])) |> render_click()
    assert has_element?(view, "#model-fixture-controls", "Next request: Failure")
    assert %{next_scenario: :failure} = ModelFixture.status(fixture)
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

  defp start_reporter(handler_id, max_pending_events) do
    child_id = {TelemetryReporter, make_ref()}

    reporter =
      start_supervised!(
        Supervisor.child_spec(
          {TelemetryReporter,
           name: nil, handler_id: handler_id, max_pending_events: max_pending_events},
          id: child_id,
          restart: :temporary
        )
      )

    {child_id, reporter}
  end

  defp configure_reporter(reporter) do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    Application.put_env(
      :vxpipe_console,
      :diagnostics,
      Keyword.put(diagnostics, :reporter, reporter)
    )
  end

  defp admit_room(prefix) do
    room_id = "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"

    :post
    |> Plug.Test.conn("/api/rooms", JSON.encode!(%{"room_id" => room_id}))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Mount.call(@room_mount_options)
  end

  defp health_request do
    :get
    |> Plug.Test.conn("/healthz")
    |> Mount.call(@room_mount_options)
  end

  defp handler_count(handler_id) do
    @runtime_sample
    |> :telemetry.list_handlers()
    |> Enum.count(fn handler -> handler.id == handler_id end)
  end

  defp registry_entries do
    Vxpipe.CallEngine.RoomRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> MapSet.new()
  end

  defp room_children do
    Vxpipe.CallEngine.RoomSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
    |> MapSet.new()
  end

  defp authenticated_conn do
    %Plug.Conn{} = conn = build_conn()
    conn = %{conn | host: "localhost", scheme: :https}

    conn
    |> Plug.Test.init_test_session(%{})
    |> InstallationOperatorSession.put()
  end
end
