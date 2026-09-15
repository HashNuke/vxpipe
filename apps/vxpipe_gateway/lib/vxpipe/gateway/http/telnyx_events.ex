defmodule Vxpipe.Gateway.HTTP.TelnyxEvents do
  @moduledoc false

  import Plug.Conn

  alias Plug.Conn.Utils
  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Gateway.HTTP.RawBody

  alias Vxpipe.Gateway.Telephony.{
    IngressHandler,
    WebhookService
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.{WebhookDecoder, WebhookVerifier}

  @spec route?(Plug.Conn.t()) :: boolean()
  def route?(%Plug.Conn{
        method: "POST",
        path_info: ["api", "telephony", "telnyx", _ingress_key, "events"]
      }),
      do: true

  def route?(%Plug.Conn{}), do: false

  @spec handle(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handle(conn, options, ingress_key) do
    with true <- options.registry.enabled?,
         :ok <- json_content_type(conn),
         {:ok, body, conn} <- RawBody.read(conn, options.maximum_body_bytes),
         {:ok, service, owner} <-
           WebhookService.select(options.registry, :telnyx, ingress_key, body),
         {:ok, headers} <- authentication_headers(conn),
         {:ok, received_at} <- received_at(options.clock),
         webhook = %Webhook{headers: headers, body: body, received_at: received_at},
         :ok <- WebhookVerifier.verify(webhook, service.verifier_options) do
      handle_verified(conn, options.handler, service, webhook, owner)
    else
      false ->
        send_resp(conn, 404, "not found")

      {:error, :wrong_provider} ->
        send_resp(conn, 404, "not found")

      {:error, :disabled} ->
        send_resp(conn, 404, "not found")

      {:error, :service_not_found} ->
        send_resp(conn, 404, "not found")

      {:error, :unsupported_media_type} ->
        send_resp(conn, 415, "expected application/json")

      {:error, :payload_too_large, conn} ->
        send_resp(conn, 413, "payload too large")

      {:error, :body_unavailable, conn} ->
        send_resp(conn, 400, "invalid webhook")

      {:error, :invalid_authentication_headers} ->
        send_resp(conn, 401, "invalid webhook authentication")

      {:error, :invalid_received_at} ->
        send_resp(conn, 503, "webhook processing unavailable")

      {:error, :invalid_webhook_authentication} ->
        send_resp(conn, 401, "invalid webhook authentication")

      {:error, :invalid_webhook_verifier_configuration} ->
        send_resp(conn, 503, "webhook processing unavailable")
    end
  end

  defp handle_verified(conn, handler, service, webhook, owner) do
    case WebhookDecoder.decode(webhook) do
      {:ok, %Event{} = event} -> dispatch(conn, handler, service, event, owner)
      :ignore -> send_resp(conn, 200, "ok")
      {:error, :invalid_telnyx_webhook} -> send_resp(conn, 400, "invalid webhook")
    end
  end

  defp dispatch(conn, handler, service, event, owner) do
    if event.provider_connection_id == service.identity.provider_connection_id do
      case IngressHandler.dispatch(handler, service, event, owner) do
        :ok -> send_resp(conn, 200, "ok")
        {:ok, _result} -> send_resp(conn, 200, "ok")
        {:error, _reason} -> send_resp(conn, 503, "webhook processing unavailable")
      end
    else
      send_resp(conn, 403, "webhook source mismatch")
    end
  end

  defp json_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [value] ->
        case Utils.media_type(value) do
          {:ok, "application", "json", _parameters} -> :ok
          _unsupported -> {:error, :unsupported_media_type}
        end

      _missing_or_duplicate ->
        {:error, :unsupported_media_type}
    end
  end

  defp authentication_headers(conn) do
    with [timestamp] <- get_req_header(conn, "telnyx-timestamp"),
         [signature] <- get_req_header(conn, "telnyx-signature-ed25519") do
      {:ok,
       %{
         "telnyx-timestamp" => timestamp,
         "telnyx-signature-ed25519" => signature
       }}
    else
      _missing_or_duplicate -> {:error, :invalid_authentication_headers}
    end
  end

  defp received_at(clock) do
    case clock.() do
      timestamp when is_integer(timestamp) and timestamp >= 0 -> {:ok, timestamp}
      _invalid -> {:error, :invalid_received_at}
    end
  end
end
