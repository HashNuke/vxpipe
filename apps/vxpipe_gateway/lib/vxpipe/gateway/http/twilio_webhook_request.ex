defmodule Vxpipe.Gateway.HTTP.TwilioWebhookRequest do
  @moduledoc false

  import Plug.Conn

  alias Plug.Conn.Utils
  alias Vxpipe.CallEngine.Telephony.{Adapter, Event, Webhook}
  alias Vxpipe.Gateway.HTTP.{RawBody, TwilioRequestSignature}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, WebhookService}

  @type endpoint_builder :: (ConfiguredService.t() -> {String.t(), map()})

  @spec ingest(Plug.Conn.t(), map(), String.t(), endpoint_builder(), String.t() | nil) ::
          {:ok, Plug.Conn.t(), ConfiguredService.t(), Event.t(), tuple() | nil}
          | {:ignore, Plug.Conn.t()}
          | {:error, term(), Plug.Conn.t()}
  def ingest(conn, options, ingress_key, endpoint_builder, local_id \\ nil) do
    with true <- options.registry.enabled?,
         :ok <- form_content_type(conn),
         {:ok, body, conn} <- RawBody.read(conn, options.maximum_body_bytes),
         {:ok, service, owner} <-
           WebhookService.select_twilio(options.registry, ingress_key, body, local_id),
         {:ok, signature} <- TwilioRequestSignature.fetch(conn),
         {url, route_parameters} <- endpoint_builder.(service),
         webhook <- webhook(body, signature, options.clock, url, route_parameters),
         result <- Adapter.ingest_webhook(service.adapter, service.adapter_options, webhook) do
      normalize_result(result, conn, service, owner)
    else
      false -> {:error, :disabled, conn}
      {:error, reason, error_conn} -> {:error, reason, error_conn}
      {:error, reason} -> {:error, reason, conn}
    end
  end

  defp normalize_result({:ok, %Event{} = event}, conn, service, owner),
    do: {:ok, conn, service, event, owner}

  defp normalize_result(:ignore, conn, _service, _owner), do: {:ignore, conn}
  defp normalize_result({:error, reason}, conn, _service, _owner), do: {:error, reason, conn}

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

  defp webhook(body, signature, clock, url, route_parameters) do
    %Webhook{
      headers: %{"x-twilio-signature" => signature},
      body: body,
      received_at: clock.(),
      route_parameters: route_parameters,
      url: url
    }
  end
end
