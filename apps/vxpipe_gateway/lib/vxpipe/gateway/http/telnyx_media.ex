defmodule Vxpipe.Gateway.HTTP.TelnyxMedia do
  @moduledoc false

  import Plug.Conn

  alias Vxpipe.Gateway.Telephony.MediaAdmission
  alias Vxpipe.Gateway.Telephony.Telnyx.MediaSocket

  @default_maximum_message_bytes 131_072
  @default_timeout_ms 30_000
  @maximum_token_bytes 128

  @spec init(keyword()) :: map()
  def init(options) do
    %{
      media_admission: Keyword.get(options, :media_admission, MediaAdmission),
      maximum_message_bytes:
        positive_integer(
          Keyword.get(options, :maximum_media_message_bytes, @default_maximum_message_bytes),
          :maximum_media_message_bytes
        ),
      socket: Keyword.get(options, :media_socket, MediaSocket),
      timeout_ms:
        positive_integer(
          Keyword.get(options, :media_socket_timeout_ms, @default_timeout_ms),
          :media_socket_timeout_ms
        )
    }
  end

  @spec upgrade(Plug.Conn.t(), map(), String.t(), String.t()) :: Plug.Conn.t()
  def upgrade(conn, options, ingress_key, token) do
    with :ok <- valid_token_shape(token),
         :ok <- validate_upgrade(conn),
         {:ok, binding} <-
           MediaAdmission.consume(options.media_admission, ingress_key, token) do
      conn
      |> WebSockAdapter.upgrade(
        options.socket,
        %{binding: binding},
        timeout: options.timeout_ms,
        max_frame_size: options.maximum_message_bytes,
        early_validate_upgrade: false
      )
      |> halt()
    else
      {:error, :invalid_upgrade} -> send_resp(conn, 400, "expected websocket upgrade")
      {:error, :invalid_media_token} -> send_resp(conn, 404, "media socket not found")
    end
  end

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

  defp positive_integer(value, _name) when is_integer(value) and value > 0, do: value

  defp positive_integer(_value, name) do
    raise ArgumentError, "#{name} must be a positive integer"
  end
end
