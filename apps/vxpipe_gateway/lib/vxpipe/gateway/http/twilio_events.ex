defmodule Vxpipe.Gateway.HTTP.TwilioEvents do
  @moduledoc false

  import Plug.Conn

  alias Plug.Conn.Utils
  alias Vxpipe.CallEngine.Telephony.{Adapter, Event, Webhook}
  alias Vxpipe.Gateway.HTTP.RawBody
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, IngressHandler, ServiceRegistry}
  alias Vxpipe.Gateway.Telephony.Twilio.{PublicEndpoint, TwiML}

  @spec route?(Plug.Conn.t()) :: boolean()
  def route?(%Plug.Conn{
        method: "POST",
        path_info: ["api", "telephony", "twilio", _ingress_key, "voice"]
      }),
      do: true

  def route?(%Plug.Conn{}), do: false

  @spec handle(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handle(conn, options, ingress_key) do
    with {:ok, service} <- ServiceRegistry.fetch(options.registry, ingress_key),
         :ok <- provider(service),
         :ok <- form_content_type(conn),
         {:ok, body, conn} <- RawBody.read(conn, options.maximum_body_bytes),
         {:ok, signature} <- signature(conn),
         webhook <- webhook(service, body, signature, options.clock),
         {:ok, %Event{kind: :incoming} = event} <-
           Adapter.ingest_webhook(service.adapter, service.adapter_options, webhook),
         {:ok, media_url} <- IngressHandler.dispatch(options.handler, service.identity, event),
         {:ok, twiml} <- TwiML.connect_stream(media_url) do
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, twiml)
    else
      {:error, reason, conn} ->
        raw_body_error(conn, reason)

      {:error, :disabled} ->
        send_resp(conn, 404, "not found")

      {:error, :service_not_found} ->
        send_resp(conn, 404, "not found")

      {:error, :wrong_provider} ->
        send_resp(conn, 404, "not found")

      {:error, :unsupported_media_type} ->
        send_resp(conn, 415, "expected form webhook")

      {:error, :invalid_authentication_headers} ->
        send_resp(conn, 401, "invalid webhook authentication")

      {:error, :invalid_twilio_webhook_authentication} ->
        send_resp(conn, 401, "invalid webhook authentication")

      {:error, :invalid_twilio_webhook_verifier_configuration} ->
        send_resp(conn, 503, "webhook processing unavailable")

      {:error, :invalid_twilio_webhook} ->
        send_resp(conn, 400, "invalid webhook")

      {:error, :invalid_twilio_media_url} ->
        send_resp(conn, 503, "webhook processing unavailable")

      {:error, _reason} ->
        send_resp(conn, 503, "webhook processing unavailable")

      :ignore ->
        send_resp(conn, 200, "ok")

      :ok ->
        send_resp(conn, 503, "webhook processing unavailable")
    end
  end

  defp provider(%ConfiguredService{identity: %{provider: :twilio}}), do: :ok
  defp provider(%ConfiguredService{}), do: {:error, :wrong_provider}

  defp form_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [value] ->
        case Utils.media_type(value) do
          {:ok, "application", "x-www-form-urlencoded", _parameters} -> :ok
          _unsupported -> {:error, :unsupported_media_type}
        end

      _missing_or_duplicate ->
        {:error, :unsupported_media_type}
    end
  end

  defp signature(conn) do
    case get_req_header(conn, "x-twilio-signature") do
      [value] when value != "" -> {:ok, value}
      _missing_or_duplicate -> {:error, :invalid_authentication_headers}
    end
  end

  defp webhook(service, body, signature, clock) do
    %Webhook{
      headers: %{"x-twilio-signature" => signature},
      body: body,
      received_at: clock.(),
      url: PublicEndpoint.voice_url(service)
    }
  end

  defp raw_body_error(conn, :payload_too_large), do: send_resp(conn, 413, "payload too large")
  defp raw_body_error(conn, :body_unavailable), do: send_resp(conn, 400, "invalid webhook")
end
