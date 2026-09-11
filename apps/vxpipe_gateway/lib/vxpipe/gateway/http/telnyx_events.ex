defmodule Vxpipe.Gateway.HTTP.TelnyxEvents do
  @moduledoc false

  import Plug.Conn

  alias Plug.Conn.Utils
  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.RawBody

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    IngressHandler,
    MediaAdmission,
    ServiceRegistry
  }

  alias Vxpipe.Gateway.Telephony.Telnyx.{WebhookDecoder, WebhookVerifier}

  @default_maximum_body_bytes 131_072

  @spec init(keyword()) :: map()
  def init(options) do
    options =
      Keyword.validate!(options,
        enabled: false,
        services: [],
        handler: {CallIngress, []},
        media_admission: MediaAdmission,
        clock: &__MODULE__.system_time_seconds/0,
        maximum_body_bytes: @default_maximum_body_bytes
      )

    registry =
      ServiceRegistry.init!(
        enabled: Keyword.fetch!(options, :enabled),
        services: Keyword.fetch!(options, :services)
      )

    handler =
      registry.enabled?
      |> handler!(Keyword.fetch!(options, :handler))
      |> configure_default_backend(registry, Keyword.fetch!(options, :media_admission))

    clock = clock!(Keyword.fetch!(options, :clock))
    maximum_body_bytes = maximum_body_bytes!(Keyword.fetch!(options, :maximum_body_bytes))

    %{
      registry: registry,
      handler: handler,
      clock: clock,
      maximum_body_bytes: maximum_body_bytes
    }
  end

  @spec route?(Plug.Conn.t()) :: boolean()
  def route?(%Plug.Conn{
        method: "POST",
        path_info: ["api", "telephony", "telnyx", _ingress_key, "events"]
      }),
      do: true

  def route?(%Plug.Conn{}), do: false

  @doc false
  @spec system_time_seconds() :: non_neg_integer()
  def system_time_seconds, do: System.system_time(:second)

  @spec handle(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handle(conn, options, ingress_key) do
    with {:ok, service} <- ServiceRegistry.fetch(options.registry, ingress_key),
         :ok <- json_content_type(conn),
         {:ok, body, conn} <- RawBody.read(conn, options.maximum_body_bytes),
         {:ok, headers} <- authentication_headers(conn),
         {:ok, received_at} <- received_at(options.clock),
         webhook = %Webhook{headers: headers, body: body, received_at: received_at},
         :ok <- WebhookVerifier.verify(webhook, service.verifier_options) do
      handle_verified(conn, options.handler, service, webhook)
    else
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

  defp handle_verified(conn, handler, service, webhook) do
    case WebhookDecoder.decode(webhook) do
      {:ok, %Event{} = event} -> dispatch(conn, handler, service, event)
      :ignore -> send_resp(conn, 200, "ok")
      {:error, :invalid_telnyx_webhook} -> send_resp(conn, 400, "invalid webhook")
    end
  end

  defp dispatch(conn, handler, service, event) do
    if event.provider_connection_id == service.identity.provider_connection_id do
      case IngressHandler.dispatch(handler, service.identity, event) do
        :ok -> send_resp(conn, 200, "ok")
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

  defp handler!(false, _handler), do: nil
  defp handler!(true, {module, _context} = handler) when is_atom(module), do: handler
  defp handler!(true, _invalid), do: raise(ArgumentError, "telephony ingress handler is required")

  defp configure_default_backend({CallIngress, options}, registry, media_admission) do
    backend =
      options
      |> Keyword.get(:backend, {CallAdmission, []})
      |> configure_call_admission(registry, media_admission)

    {CallIngress, Keyword.put(options, :backend, backend)}
  end

  defp configure_default_backend(handler, _registry, _media_admission), do: handler

  defp configure_call_admission({CallAdmission, options}, registry, media_admission) do
    options =
      options
      |> Keyword.put(:service_registry, registry)
      |> Keyword.put(:media_admission, media_admission)

    {CallAdmission, options}
  end

  defp configure_call_admission(backend, _registry, _media_admission), do: backend

  defp clock!(clock) when is_function(clock, 0), do: clock
  defp clock!(_invalid), do: raise(ArgumentError, "telephony ingress clock must be a function/0")

  defp maximum_body_bytes!(value) when is_integer(value) and value > 0, do: value

  defp maximum_body_bytes!(_invalid),
    do: raise(ArgumentError, "telephony maximum_body_bytes must be a positive integer")
end
