defmodule Vxpipe.Gateway.TwilioFixture do
  @moduledoc false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.ConfiguredService
  alias Vxpipe.Gateway.Telephony.Twilio.{MediaSocket, PublicEndpoint}

  def post_voice(endpoint, service_options, parameters) do
    {:ok, service} = ConfiguredService.new(service_options)
    url = PublicEndpoint.voice_url(service)
    body = URI.encode_query(parameters)

    :post
    |> conn(URI.parse(url).path, body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header(
      "x-twilio-signature",
      signature(url, parameters, Keyword.fetch!(service_options, :auth_token))
    )
    |> Endpoint.call(endpoint)
  end

  def open_media(endpoint, service_options, media_url, call_sid, stream_sid) do
    auth_token = Keyword.fetch!(service_options, :auth_token)

    upgraded =
      :get
      |> conn(URI.parse(media_url).path)
      |> websocket_headers(media_url)
      |> put_req_header("x-twilio-signature", signature(media_url, %{}, auth_token))
      |> Endpoint.call(endpoint)

    with 101 <- upgraded.status,
         [
           {:websocket,
            {MediaSocket, %{binding: binding, clock: clock},
             [timeout: 30_000, max_frame_size: 131_072, early_validate_upgrade: false]}}
         ] <- sent_upgrades(upgraded),
         {:ok, socket} <- MediaSocket.init(%{binding: binding, clock: clock}),
         {:ok, socket} <- MediaSocket.handle_in(text(start(call_sid, stream_sid)), socket) do
      {:ok, binding, socket}
    else
      _invalid -> {:error, :media_harness_failed}
    end
  end

  def incoming_parameters(account_sid, call_sid) do
    %{
      "AccountSid" => account_sid,
      "CallSid" => call_sid,
      "CallStatus" => "ringing",
      "Direction" => "inbound",
      "From" => "+15550001001",
      "To" => "+15550001000"
    }
  end

  def dtmf(stream_sid, sequence_number, digit) do
    text(%{
      "event" => "dtmf",
      "sequenceNumber" => Integer.to_string(sequence_number),
      "streamSid" => stream_sid,
      "dtmf" => %{"track" => "inbound_track", "digit" => digit}
    })
  end

  def output_message(output), do: {:vxpipe_twilio_socket_send, output}

  defp start(call_sid, stream_sid) do
    %{
      "event" => "start",
      "sequenceNumber" => "1",
      "streamSid" => stream_sid,
      "start" => %{
        "accountSid" => "AC00000000000000000000000000000000",
        "callSid" => call_sid,
        "streamSid" => stream_sid,
        "tracks" => ["inbound"],
        "mediaFormat" => %{
          "encoding" => "audio/x-mulaw",
          "sampleRate" => 8_000,
          "channels" => 1
        },
        "customParameters" => %{}
      }
    }
  end

  defp signature(url, parameters, auth_token) do
    signed =
      parameters
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce(url, fn {key, value}, input -> input <> key <> value end)

    :crypto.mac(:hmac, :sha, auth_token, signed)
    |> Base.encode64()
  end

  defp websocket_headers(conn, media_url) do
    host = URI.parse(media_url).host
    conn = %{conn | host: host, req_headers: [{"host", host}]}

    conn
    |> put_req_header("connection", "upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
    |> put_req_header("sec-websocket-version", "13")
  end

  defp text(message), do: {JSON.encode!(message), opcode: :text}
end
