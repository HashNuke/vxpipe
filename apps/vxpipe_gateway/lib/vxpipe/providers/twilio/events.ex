defmodule Vxpipe.Providers.Twilio.Events do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Providers.Twilio.WebhookRequest
  alias Vxpipe.Gateway.Telephony.IngressHandler
  alias Vxpipe.Providers.Twilio.{PublicEndpoint, TwiML}

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

    with {:ok, conn, service, %Event{kind: :incoming} = event, owner} <-
           WebhookRequest.ingest(conn, options, ingress_key, endpoint),
         {:ok, media_url} <- IngressHandler.dispatch(options.handler, service, event, owner),
         {:ok, twiml} <- TwiML.connect_stream(media_url) do
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, twiml)
    else
      {:ignore, conn} -> send_resp(conn, 200, "ok")
      {:error, reason, conn} -> error_response(conn, reason)
      {:error, reason} -> reject(conn, 503, reason, "webhook processing unavailable")
      :ok -> reject(conn, 503, :invalid_voice_response, "webhook processing unavailable")
    end
  end

  @spec handle_callback(Plug.Conn.t(), map(), String.t(), String.t()) :: Plug.Conn.t()
  def handle_callback(conn, options, ingress_key, leg_id) do
    endpoint = fn service ->
      {PublicEndpoint.event_url(service, leg_id), %{"leg_id" => leg_id}}
    end

    with {:ok, conn, service, %Event{} = event, owner} <-
           WebhookRequest.ingest(conn, options, ingress_key, endpoint, leg_id),
         result <- IngressHandler.dispatch(options.handler, service, event, owner) do
      callback_response(conn, result)
    else
      {:ignore, conn} -> send_resp(conn, 200, "ok")
      {:error, reason, conn} -> error_response(conn, reason)
    end
  end

  defp callback_response(conn, :ok), do: send_resp(conn, 200, "ok")
  defp callback_response(conn, {:ok, _result}), do: send_resp(conn, 200, "ok")

  defp callback_response(conn, {:error, reason}),
    do: reject(conn, 503, reason, "webhook processing unavailable")

  defp error_response(conn, :payload_too_large),
    do: reject(conn, 413, :payload_too_large, "payload too large")

  defp error_response(conn, :body_unavailable),
    do: reject(conn, 400, :body_unavailable, "invalid webhook")

  defp error_response(conn, :disabled), do: reject(conn, 404, :disabled, "not found")

  defp error_response(conn, :service_not_found),
    do: reject(conn, 404, :service_not_found, "not found")

  defp error_response(conn, :wrong_provider), do: reject(conn, 404, :wrong_provider, "not found")

  defp error_response(conn, :unsupported_media_type),
    do: reject(conn, 415, :unsupported_media_type, "expected form webhook")

  defp error_response(conn, :invalid_authentication_headers),
    do: reject(conn, 401, :invalid_authentication_headers, "invalid webhook authentication")

  defp error_response(conn, :invalid_twilio_webhook_authentication),
    do:
      reject(conn, 401, :invalid_twilio_webhook_authentication, "invalid webhook authentication")

  defp error_response(conn, :invalid_twilio_webhook_verifier_configuration),
    do:
      reject(
        conn,
        503,
        :invalid_twilio_webhook_verifier_configuration,
        "webhook processing unavailable"
      )

  defp error_response(conn, :invalid_twilio_webhook),
    do: reject(conn, 400, :invalid_twilio_webhook, "invalid webhook")

  defp error_response(conn, reason),
    do: reject(conn, 503, reason, "webhook processing unavailable")

  defp reject(conn, status, reason, body) do
    Vxpipe.Gateway.Telemetry.webhook_failure(:twilio, status, reason)
    send_resp(conn, status, body)
  end
end
