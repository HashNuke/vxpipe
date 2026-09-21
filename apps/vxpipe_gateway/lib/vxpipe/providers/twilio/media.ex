defmodule Vxpipe.Providers.Twilio.Media do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.CallEngine.Telephony.Webhook
  alias Vxpipe.Providers.Twilio.RequestSignature

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    MediaAdmission,
    MediaBinding
  }

  alias Vxpipe.Providers.Twilio.{TelephonyMediaSocket, PublicEndpoint, WebhookVerifier}

  @default_maximum_message_bytes 131_072
  @default_timeout_ms 30_000
  @maximum_token_bytes 128

  @spec route?(Plug.Conn.t()) :: boolean()
  def route?(%Plug.Conn{
        method: "GET",
        path_info: ["api", "telephony", "twilio", _ingress_key, "media", _token]
      }),
      do: true

  def route?(%Plug.Conn{}), do: false

  @spec init(keyword()) :: map()
  def init(options) do
    %{
      clock: Keyword.fetch!(options, :clock),
      media_admission: Keyword.get(options, :media_admission, MediaAdmission),
      maximum_message_bytes:
        positive_integer(
          Keyword.get(options, :maximum_media_message_bytes, @default_maximum_message_bytes),
          :maximum_media_message_bytes
        ),
      enabled?: Keyword.fetch!(options, :registry).enabled?,
      socket: Keyword.get(options, :twilio_media_socket, TelephonyMediaSocket),
      timeout_ms:
        positive_integer(
          Keyword.get(options, :media_socket_timeout_ms, @default_timeout_ms),
          :media_socket_timeout_ms
        )
    }
  end

  @spec upgrade(Plug.Conn.t(), map(), String.t(), String.t()) :: Plug.Conn.t()
  def upgrade(conn, options, ingress_key, token) do
    with :ok <- enabled(options),
         :ok <- valid_token_shape(token),
         :ok <- validate_upgrade(conn),
         {:ok, service} <-
           lookup_admission_service(options.media_admission, ingress_key, token),
         :ok <- twilio_service(service),
         {:ok, signature} <- RequestSignature.fetch(conn),
         :ok <- authenticate(service, token, signature, options.clock),
         {:ok, binding} <-
           consume_admission(options.media_admission, ingress_key, token, service),
         :ok <- matching_binding(binding, service) do
      conn
      |> WebSockAdapter.upgrade(
        options.socket,
        %{binding: binding, clock: options.clock},
        timeout: options.timeout_ms,
        max_frame_size: options.maximum_message_bytes,
        early_validate_upgrade: false
      )
      |> halt()
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  defp enabled(%{enabled?: true}), do: :ok
  defp enabled(_options), do: {:error, :disabled}

  defp lookup_admission_service(server, ingress_key, token) do
    MediaAdmission.lookup_service(server, ingress_key, token)
  catch
    :exit, _reason -> {:error, :media_admission_unavailable}
  end

  defp consume_admission(server, ingress_key, token, service) do
    MediaAdmission.consume(server, ingress_key, token, service)
  catch
    :exit, _reason -> {:error, :media_admission_unavailable}
  end

  defp authenticate(service, token, signature, clock) do
    webhook = %Webhook{
      headers: %{"x-twilio-signature" => signature},
      body: "",
      received_at: clock.(),
      url: PublicEndpoint.media_url(service, token)
    }

    WebhookVerifier.verify(webhook, service.verifier_options)
  end

  defp matching_binding(%MediaBinding{} = binding, %ConfiguredService{} = service) do
    identity = service.identity

    if MediaBinding.valid?(binding) and binding.provider == :twilio and
         identity.scope == {:tenant, binding.tenant_id} and
         binding.service_id == identity.service_id and binding.ingress_key == identity.ingress_key and
         binding.provider_connection_id == identity.provider_connection_id,
       do: :ok,
       else: {:error, :invalid_media_token}
  end

  defp twilio_service(%ConfiguredService{identity: %{provider: :twilio}}), do: :ok
  defp twilio_service(%ConfiguredService{}), do: {:error, :service_not_found}

  defp validate_upgrade(conn) do
    case WebSockAdapter.UpgradeValidation.validate_upgrade(conn) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid_upgrade}
    end
  end

  defp valid_token_shape(token)
       when is_binary(token) and byte_size(token) >= 32 and
              byte_size(token) <= @maximum_token_bytes,
       do: :ok

  defp valid_token_shape(_invalid), do: {:error, :invalid_media_token}

  defp error_response(conn, :invalid_upgrade),
    do: send_resp(conn, 400, "expected websocket upgrade")

  defp error_response(conn, reason)
       when reason in [:disabled, :service_not_found, :invalid_media_token],
       do: send_resp(conn, 404, "media socket not found")

  defp error_response(conn, reason)
       when reason in [
              :invalid_authentication_headers,
              :invalid_twilio_webhook_authentication
            ],
       do: send_resp(conn, 401, "invalid media authentication")

  defp error_response(conn, _reason),
    do: send_resp(conn, 503, "media socket unavailable")

  defp positive_integer(value, _name) when is_integer(value) and value > 0, do: value

  defp positive_integer(_value, name) do
    raise ArgumentError, "#{name} must be a positive integer"
  end
end
