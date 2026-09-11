defmodule Vxpipe.Gateway.HTTP.TwilioWebhookRequest do
  @moduledoc false

  import Plug.Conn

  alias Plug.Conn.Utils
  alias Vxpipe.CallEngine.Telephony.{Adapter, Event, Webhook}
  alias Vxpipe.Gateway.HTTP.RawBody
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, ServiceRegistry}

  @type endpoint_builder :: (ConfiguredService.t() -> {String.t(), map()})

  @spec ingest(Plug.Conn.t(), map(), String.t(), endpoint_builder()) ::
          {:ok, Plug.Conn.t(), ConfiguredService.t(), Event.t()}
          | {:ignore, Plug.Conn.t()}
          | {:error, term(), Plug.Conn.t()}
  def ingest(conn, options, ingress_key, endpoint_builder) do
    with {:ok, service} <- ServiceRegistry.fetch(options.registry, ingress_key),
         :ok <- provider(service),
         :ok <- form_content_type(conn),
         {:ok, body, conn} <- RawBody.read(conn, options.maximum_body_bytes),
         {:ok, signature} <- signature(conn),
         {url, route_parameters} <- endpoint_builder.(service),
         webhook <- webhook(body, signature, options.clock, url, route_parameters),
         result <- Adapter.ingest_webhook(service.adapter, service.adapter_options, webhook) do
      normalize_result(result, conn, service)
    else
      {:error, reason, error_conn} -> {:error, reason, error_conn}
      {:error, reason} -> {:error, reason, conn}
    end
  end

  defp normalize_result({:ok, %Event{} = event}, conn, service),
    do: {:ok, conn, service, event}

  defp normalize_result(:ignore, conn, _service), do: {:ignore, conn}
  defp normalize_result({:error, reason}, conn, _service), do: {:error, reason, conn}

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
