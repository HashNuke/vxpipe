defmodule Vxpipe.Providers.Telnyx.AdapterTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Vxpipe.CallEngine.Telephony.{Adapter, Answer, Dial, EndLeg, LegReference, Submission}
  alias Vxpipe.Providers.Telnyx.Adapter, as: TelnyxAdapter

  setup :verify_on_exit!

  test "dials an authorized leg with bidirectional Opus media and no automatic retry" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v2/calls"
      assert get_req_header(conn, "authorization") == ["Bearer test-api-key"]

      body = JSON.decode!(Req.Test.raw_body(conn))

      assert %{
               "connection_id" => "voice-application-1",
               "from" => "+15550001000",
               "to" => "+15550001001",
               "webhook_url" => "https://voice.example.test/telnyx/events",
               "webhook_url_method" => "POST",
               "stream_url" => "wss://voice.example.test/telnyx/media/leg-outbound",
               "stream_track" => "inbound_track",
               "stream_codec" => "OPUS",
               "stream_bidirectional_mode" => "rtp",
               "stream_bidirectional_codec" => "OPUS",
               "stream_bidirectional_sampling_rate" => 16_000,
               "stream_bidirectional_target_legs" => "self",
               "answering_machine_detection" => "detect",
               "command_id" => "leg-outbound"
             } = body

      assert %{"vxpipe_leg_id" => "leg-outbound"} =
               body["client_state"] |> Base.decode64!() |> JSON.decode!()

      Req.Test.json(conn, %{
        data: %{
          call_control_id: "call-control-outbound",
          call_leg_id: "provider-leg-outbound",
          call_session_id: "provider-session-outbound"
        }
      })
    end)

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: "call-control-outbound",
              provider_call_leg_id: "provider-leg-outbound",
              provider_call_session_id: "provider-session-outbound"
            }} = Adapter.dial(TelnyxAdapter, config(), dial())
  end

  test "answers an adopted leg and starts the same media contract" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v2/calls/call-control-inbound/actions/answer"

      body = JSON.decode!(Req.Test.raw_body(conn))

      assert %{
               "stream_url" => "wss://voice.example.test/telnyx/media/leg-inbound",
               "stream_track" => "inbound_track",
               "stream_codec" => "OPUS",
               "stream_bidirectional_mode" => "rtp",
               "stream_bidirectional_codec" => "OPUS",
               "stream_bidirectional_sampling_rate" => 16_000,
               "stream_bidirectional_target_legs" => "self",
               "command_id" => "answer-leg-inbound"
             } = body

      assert %{"vxpipe_leg_id" => "leg-inbound"} =
               body["client_state"] |> Base.decode64!() |> JSON.decode!()

      Req.Test.json(conn, %{data: %{result: "ok"}})
    end)

    request = %Answer{
      leg: leg_reference("leg-inbound", "call-control-inbound"),
      media_url: "wss://voice.example.test/telnyx/media/leg-inbound"
    }

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: "call-control-inbound"
            }} = Adapter.answer(TelnyxAdapter, config(), request)
  end

  test "submits the packaged callback recording directly to the affected carrier leg" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v2/calls/known-leg/actions/playback_start"

      assert %{
               "target_legs" => "self",
               "command_id" => "recovery-known-leg",
               "client_state" => encoded,
               "audio_type" => "wav",
               "playback_content" => audio
             } =
               JSON.decode!(Req.Test.raw_body(conn))

      assert Base.decode64!(encoded) == "recovery-known-leg"
      assert <<"RIFF", _::32-little, "WAVE", _::binary>> = Base.decode64!(audio)
      Req.Test.json(conn, %{data: %{result: "ok"}})
    end)

    assert {:ok, %Submission{status: :accepted}} =
             TelnyxAdapter.play_recovery_prompt(config(), "known-leg", "recovery-known-leg")
  end

  test "transfer announcement plays the separate recording on the original phone leg" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v2/calls/caller-control/actions/playback_start"
      body = JSON.decode!(Req.Test.raw_body(conn))
      assert body["target_legs"] == "self"
      assert Base.decode64!(body["client_state"]) == "recovery-transfer-leg"
      clip = Base.decode64!(body["playback_content"])
      assert <<"RIFF", _::32-little, "WAVE", _::binary>> = clip

      refute clip ==
               File.read!(Application.app_dir(:vxpipe_gateway, "priv/telephony/callback.wav"))

      Req.Test.json(conn, %{data: %{result: "ok"}})
    end)

    assert {:ok, %Submission{status: :accepted}} =
             TelnyxAdapter.play_recovery_prompt(
               config(),
               "caller-control",
               "recovery-transfer-leg",
               :transfer
             )
  end

  test "recovery dials a single carrier-linked leg with bounded ringing" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v2/calls"
      body = JSON.decode!(Req.Test.raw_body(conn))

      assert %{
               "link_to" => "original-control",
               "bridge_on_answer" => true,
               "prevent_double_bridge" => true,
               "retry_on_timeout" => false,
               "timeout_secs" => 20,
               "command_id" => "recovery-peer",
               "from" => "+15550001000",
               "to" => "+15550001002"
             } = body

      assert {:ok, "recovery-peer"} =
               Vxpipe.Providers.Telnyx.ClientState.decode(body["client_state"])

      refute Map.has_key?(body, "stream_url")

      Req.Test.json(conn, %{
        data: %{
          call_control_id: "peer-control",
          call_leg_id: "peer-leg",
          call_session_id: "shared-session"
        }
      })
    end)

    request = %{
      id: "recovery-peer",
      caller: "original-control",
      from: "+15550001000",
      to: "+15550001002",
      callback_url: "https://voice.example.test/webhooks/platform/telnyx",
      timeout_secs: 20
    }

    assert {:ok,
            %Submission{
              provider_call_control_id: "peer-control",
              provider_call_leg_id: "peer-leg",
              provider_call_session_id: "shared-session"
            }} =
             TelnyxAdapter.dial_recovery_peer(config(), request)
  end

  test "hangs up only the exact known provider leg" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v2/calls/call-control-outbound/actions/hangup"
      assert %{"command_id" => "hangup-leg-outbound"} = JSON.decode!(Req.Test.raw_body(conn))
      Req.Test.json(conn, %{data: %{result: "ok"}})
    end)

    request = %EndLeg{
      leg: leg_reference("leg-outbound", "call-control-outbound"),
      reason: :transfer_failed
    }

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: "call-control-outbound"
            }} = Adapter.end_leg(TelnyxAdapter, config(), request)
  end

  test "returns an unknown dial outcome after one ambiguous provider response" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> put_status(503)
      |> Req.Test.json(%{errors: [%{title: "temporarily unavailable"}]})
    end)

    assert {:ok, %Submission{status: :unknown, provider_call_control_id: nil}} =
             Adapter.dial(TelnyxAdapter, config(), dial())
  end

  test "returns a bounded rejection without exposing the provider response body" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> put_status(422)
      |> Req.Test.json(%{errors: [%{title: "destination rejected", detail: "private detail"}]})
    end)

    assert {:error, {:telnyx_command_rejected, 422}} =
             Adapter.dial(TelnyxAdapter, config(), dial())
  end

  test "rejects missing command credentials as configuration rather than an unknown submission" do
    options = Keyword.delete(config(), :api_key)

    assert {:error, {:missing_telnyx_option, :api_key}} =
             Adapter.dial(TelnyxAdapter, options, dial())
  end

  defp config do
    [
      api_key: "test-api-key",
      provider_connection_id: "voice-application-1",
      base_url: "http://example.test/v2",
      request_options: [plug: {Req.Test, __MODULE__}]
    ]
  end

  defp dial do
    %Dial{
      leg_id: "leg-outbound",
      from: "+15550001000",
      to: "+15550001001",
      callback_url: "https://voice.example.test/telnyx/events",
      media_url: "wss://voice.example.test/telnyx/media/leg-outbound",
      answering_machine_detection: :detect
    }
  end

  defp leg_reference(leg_id, call_control_id) do
    %LegReference{leg_id: leg_id, provider_call_control_id: call_control_id}
  end

  defp verify_on_exit!(_context) do
    Req.Test.verify_on_exit!()
    :ok
  end
end
