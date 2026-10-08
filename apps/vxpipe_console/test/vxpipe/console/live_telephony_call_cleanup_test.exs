defmodule Vxpipe.Console.LiveTelephonyCallCleanupTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Answer, Dial, Event, LegReference, Submission}
  alias Vxpipe.Console.Test.LiveTelephonyCallCleanup

  setup do
    Req.Test.verify_on_exit!()
    tracker = start_supervised!(LiveTelephonyCallCleanup)
    scope = LiveTelephonyCallCleanup.open(tracker)
    %{tracker: tracker, scope: scope}
  end

  test "dial captures the handle before test assertions and teardown verifies it", context do
    options = [
      api_key: "synthetic-key",
      provider_connection_id: "app",
      request_options: [plug: {Req.Test, __MODULE__}]
    ]

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v2/calls"

      Req.Test.json(conn, %{
        data: %{call_control_id: "captured", call_leg_id: "leg", call_session_id: "session"}
      })
    end)

    request = %Dial{
      leg_id: "local-leg",
      from: "+13125550142",
      to: "+13125550143",
      callback_url: "https://voice.example/events",
      media_url: "wss://voice.example/media",
      answering_machine_detection: :disabled
    }

    assert {:ok, %Submission{provider_call_control_id: "captured"}} =
             LiveTelephonyCallCleanup.command(:telnyx, :dial, options, request, context.tracker)

    expect_hangup("captured")
    assert :ok = LiveTelephonyCallCleanup.close(context.scope, context.tracker)
  end

  test "duplicate callback handles are cleaned once", context do
    options = options()

    for _duplicate <- 1..2 do
      assert :ok =
               LiveTelephonyCallCleanup.record(
                 context.scope,
                 :telnyx,
                 options,
                 "captured",
                 context.tracker
               )
    end

    expect_hangup("captured")
    assert :ok = LiveTelephonyCallCleanup.close(context.scope, context.tracker)
    assert :ok = LiveTelephonyCallCleanup.close(context.scope, context.tracker)
  end

  test "teardown continues through failures and reports sanitized results", context do
    assert :ok =
             LiveTelephonyCallCleanup.record(
               context.scope,
               :telnyx,
               options(),
               "first",
               context.tracker
             )

    assert :ok =
             LiveTelephonyCallCleanup.record(
               context.scope,
               :telnyx,
               options(),
               "second",
               context.tracker
             )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v2/calls/first"
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{message: "private error body"})
    end)

    expect_hangup("second")

    assert {:error, [{:live_call_cleanup, :telnyx, :unverified}]} =
             LiveTelephonyCallCleanup.close(context.scope, context.tracker)
  end

  test "a handle arriving after teardown is ended immediately", context do
    assert :ok = LiveTelephonyCallCleanup.close(context.scope, context.tracker)
    _next_scope = LiveTelephonyCallCleanup.open(context.tracker)
    expect_hangup("late")

    assert :ok =
             LiveTelephonyCallCleanup.record(
               context.scope,
               :telnyx,
               options(),
               "late",
               context.tracker
             )
  end

  test "authenticated initiated callbacks capture only calls involving fixture numbers",
       context do
    scope = LiveTelephonyCallCleanup.open(context.tracker, ["+13125550142"])

    for {handle, to} <- [{"captured", "+13125550142"}, {"foreign", "+13125550100"}] do
      event = %Event{
        kind: :incoming,
        provider: :telnyx,
        provider_call_control_id: handle,
        from: "+14155550199",
        to: to
      }

      assert :ok =
               LiveTelephonyCallCleanup.observe(
                 scope,
                 :telnyx,
                 options(),
                 {:ok, event},
                 context.tracker
               )
    end

    expect_hangup("captured")
    assert :ok = LiveTelephonyCallCleanup.close(scope, context.tracker)
  end

  test "a failed answer still leaves its known incoming handle in teardown", context do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v2/calls/captured/actions/answer"
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{errors: []})
    end)

    request = %Answer{
      leg: %LegReference{leg_id: "local-leg", provider_call_control_id: "captured"},
      media_url: "wss://voice.example/media"
    }

    assert {:error, {:telnyx_command_rejected, 401}} =
             LiveTelephonyCallCleanup.command(
               :telnyx,
               :answer,
               options(),
               request,
               context.tracker
             )

    expect_hangup("captured")
    assert :ok = LiveTelephonyCallCleanup.close(context.scope, context.tracker)
  end

  defp expect_hangup(handle) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v2/calls/#{handle}"
      Req.Test.json(conn, %{data: %{is_alive: true}})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v2/calls/#{handle}/actions/hangup"
      Req.Test.json(conn, %{data: %{result: "ok"}})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{data: %{is_alive: false}})
    end)
  end

  defp options, do: [api_key: "synthetic-key", request_options: [plug: {Req.Test, __MODULE__}]]
end
