defmodule Vxpipe.Gateway.LiveCallCleanupTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.TestLiveCallCleanup

  setup do
    Req.Test.verify_on_exit!()
    :ok
  end

  test "Telnyx teardown ends and verifies only the captured call handle" do
    telnyx_status(true)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v2/calls/opaque%2Fcontrol/actions/hangup"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer synthetic-key"]
      Req.Test.json(conn, %{data: %{result: "ok"}})
    end)

    telnyx_status(false)
    assert :ok = TestLiveCallCleanup.hangup(:telnyx, telnyx_options(), "opaque/control")
  end

  for state <- ["queued", "ringing", "in-progress"] do
    @state state
    test "Twilio teardown ends a #{@state} call by its captured SID" do
      terminal = if @state == "in-progress", do: "completed", else: "canceled"
      twilio_status(@state)

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/2010-04-01/Accounts/ACsynthetic/Calls/CAsynthetic.json"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert URI.decode_query(body) == %{"Status" => terminal}
        Req.Test.json(conn, %{sid: "CAsynthetic", status: terminal})
      end)

      twilio_status(terminal)
      assert :ok = TestLiveCallCleanup.hangup(:twilio, twilio_options(), "CAsynthetic")
    end
  end

  test "an already-ended call is verified without another hangup" do
    telnyx_status(false)
    assert :ok = TestLiveCallCleanup.hangup(:telnyx, telnyx_options(), "opaque/control")
  end

  test "an ended paired leg succeeds even when its hangup was rejected" do
    telnyx_status(true)

    Req.Test.expect(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{errors: [%{code: "90018"}]})
    end)

    telnyx_status(false)
    assert :ok = TestLiveCallCleanup.hangup(:telnyx, telnyx_options(), "opaque/control")
  end

  test "an accepted hangup with a still-live call fails teardown" do
    telnyx_status(true)
    Req.Test.expect(__MODULE__, &Req.Test.json(&1, %{data: %{result: "ok"}}))
    telnyx_status(true)

    assert {:error, {:live_call_cleanup, :telnyx, :still_active}} =
             TestLiveCallCleanup.hangup(:telnyx, telnyx_options(), "opaque/control")
  end

  test "unverified responses return a sanitized failure without echoing carrier data" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{message: "synthetic-key opaque/control"})
    end)

    assert {:error, {:live_call_cleanup, :telnyx, :unverified}} =
             TestLiveCallCleanup.hangup(:telnyx, telnyx_options(), "opaque/control")
  end

  defp telnyx_status(alive?) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v2/calls/opaque%2Fcontrol"
      Req.Test.json(conn, %{data: %{is_alive: alive?}})
    end)
  end

  defp twilio_status(status) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/2010-04-01/Accounts/ACsynthetic/Calls/CAsynthetic.json"
      Req.Test.json(conn, %{sid: "CAsynthetic", status: status})
    end)
  end

  defp telnyx_options,
    do: [api_key: "synthetic-key", request_options: [plug: {Req.Test, __MODULE__}]]

  defp twilio_options do
    [
      account_sid: "ACsynthetic",
      auth_token: "synthetic-token",
      request_options: [plug: {Req.Test, __MODULE__}]
    ]
  end
end
