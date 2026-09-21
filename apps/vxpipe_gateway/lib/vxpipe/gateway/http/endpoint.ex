defmodule Vxpipe.Gateway.HTTP.Endpoint do
  @moduledoc false

  @behaviour Plug

  alias Vxpipe.Gateway.HTTP.{Cors, Router}
  alias Vxpipe.Gateway.Telemetry, as: GatewayTelemetry
  alias Vxpipe.Providers.Telnyx
  alias Vxpipe.Providers.Twilio

  @impl true
  def init(options) do
    %{
      cors: options |> Keyword.get(:cors, []) |> Cors.init(),
      parsers:
        Plug.Parsers.init(
          parsers: [:json],
          pass: [],
          json_decoder: JSON,
          length: 131_072
        ),
      router:
        Router.init(
          call_spec_authoring: Keyword.get(options, :call_spec_authoring, []),
          operator_api: Keyword.get(options, :operator_api, []),
          call_admission: Keyword.get(options, :call_admission, []),
          room_creation: Keyword.get(options, :room_creation, []),
          telephony: Keyword.get(options, :telephony, []),
          webrtc: Keyword.get(options, :webrtc, [])
        )
    }
  end

  @impl true
  def call(conn, %{cors: cors_options, parsers: parser_options, router: router_options}) do
    GatewayTelemetry.observe_request(conn, fn ->
      conn = Cors.call(conn, cors_options)

      if conn.halted do
        conn
      else
        parse_and_route(conn, parser_options, router_options)
      end
    end)
  end

  defp parse_and_route(conn, parser_options, router_options) do
    if Telnyx.Events.route?(conn) or Twilio.Events.route?(conn) or Twilio.Media.route?(conn) do
      Router.call(conn, router_options)
    else
      conn
      |> Plug.Parsers.call(parser_options)
      |> Router.call(router_options)
    end
  end
end
