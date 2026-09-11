defmodule Vxpipe.Gateway.HTTP.TwilioEvents do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.HTTP.TwilioWebhookRequest
  alias Vxpipe.Gateway.Telephony.IngressHandler
  alias Vxpipe.Gateway.Telephony.Twilio.{PublicEndpoint, TwiML}

  @spec route?(Plug.Conn.t()) :: boolean()
  def route?(%Plug.Conn{
        method: "POST",
        path_info: ["api", "telephony", "twilio", _ingress_key, "voice"]
      }),
      do: true

  def route?(%Plug.Conn{
        method: "POST",
        path_info: ["api", "telephony", "twilio", _ingress_key, "events", _leg_id]
      }),
      do: true

  def route?(%Plug.Conn{}), do: false

  @spec handle_voice(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handle_voice(conn, options, ingress_key) do
    endpoint = fn service -> {PublicEndpoint.voice_url(service), %{}} end

    with {:ok, conn, service, %Event{kind: :incoming} = event} <-
           TwilioWebhookRequest.ingest(conn, options, ingress_key, endpoint),
         {:ok, media_url} <- IngressHandler.dispatch(options.handler, service.identity, event),
         {:ok, twiml} <- TwiML.connect_stream(media_url) do
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, twiml)
    else
      {:ignore, conn} -> send_resp(conn, 200, "ok")
      {:error, reason, conn} -> error_response(conn, reason)
      {:error, _reason} -> send_resp(conn, 503, "webhook processing unavailable")
      :ok -> send_resp(conn, 503, "webhook processing unavailable")
    end
  end

  @spec handle_callback(Plug.Conn.t(), map(), String.t(), String.t()) :: Plug.Conn.t()
  def handle_callback(conn, options, ingress_key, leg_id) do
    endpoint = fn service ->
      {PublicEndpoint.event_url(service, leg_id), %{"leg_id" => leg_id}}
    end

    with {:ok, conn, service, %Event{} = event} <-
           TwilioWebhookRequest.ingest(conn, options, ingress_key, endpoint),
         result <- IngressHandler.dispatch(options.handler, service.identity, event) do
      callback_response(conn, result)
    else
      {:ignore, conn} -> send_resp(conn, 200, "ok")
      {:error, reason, conn} -> error_response(conn, reason)
    end
  end

  defp callback_response(conn, :ok), do: send_resp(conn, 200, "ok")
  defp callback_response(conn, {:ok, _result}), do: send_resp(conn, 200, "ok")

  defp callback_response(conn, {:error, _reason}),
    do: send_resp(conn, 503, "webhook processing unavailable")

  defp error_response(conn, :payload_too_large), do: send_resp(conn, 413, "payload too large")
  defp error_response(conn, :body_unavailable), do: send_resp(conn, 400, "invalid webhook")
  defp error_response(conn, :disabled), do: send_resp(conn, 404, "not found")
  defp error_response(conn, :service_not_found), do: send_resp(conn, 404, "not found")
  defp error_response(conn, :wrong_provider), do: send_resp(conn, 404, "not found")

  defp error_response(conn, :unsupported_media_type),
    do: send_resp(conn, 415, "expected form webhook")

  defp error_response(conn, :invalid_authentication_headers),
    do: send_resp(conn, 401, "invalid webhook authentication")

  defp error_response(conn, :invalid_twilio_webhook_authentication),
    do: send_resp(conn, 401, "invalid webhook authentication")

  defp error_response(conn, :invalid_twilio_webhook_verifier_configuration),
    do: send_resp(conn, 503, "webhook processing unavailable")

  defp error_response(conn, :invalid_twilio_webhook),
    do: send_resp(conn, 400, "invalid webhook")

  defp error_response(conn, _reason), do: send_resp(conn, 503, "webhook processing unavailable")
end
