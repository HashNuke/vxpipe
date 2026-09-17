defmodule Vxpipe.Console.OperatorLoginCredentials do
  @moduledoc false

  @behaviour Plug

  alias Plug.Conn
  alias Plug.Crypto.MessageEncryptor
  alias Vxpipe.Console.OperatorLoginConfiguration

  @private_key :vxpipe_operator_login_credentials
  @aad "vxpipe.operator-login.credentials.v1"

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{method: "POST", path_info: ["auth", "login-token"]} = conn, _options) do
    conn =
      case conn.params do
        %{"operator" => %{"token" => token, "code" => code}}
        when is_binary(token) and is_binary(code) ->
          store_encrypted(conn, token, code)

        _invalid ->
          conn
      end

    redact_params(conn)
  end

  def call(%Conn{} = conn, _options), do: conn

  @spec fetch(Conn.t()) :: {:ok, binary(), binary()} | :error
  def fetch(%Conn{} = conn) do
    with encrypted when is_binary(encrypted) <- conn.private[@private_key],
         {:ok, secret} <- OperatorLoginConfiguration.session_secret(),
         {:ok, plain_text} <- MessageEncryptor.decrypt(encrypted, @aad, secret, ""),
         {token, code} when is_binary(token) and is_binary(code) <-
           :erlang.binary_to_term(plain_text, [:safe]) do
      {:ok, token, code}
    else
      _invalid -> :error
    end
  end

  defp store_encrypted(conn, token, code) do
    case OperatorLoginConfiguration.session_secret() do
      {:ok, secret} ->
        encrypted =
          {token, code}
          |> :erlang.term_to_binary()
          |> MessageEncryptor.encrypt(@aad, secret, "")

        Conn.put_private(conn, @private_key, encrypted)

      {:error, :invalid_operator_login_secret} ->
        conn
    end
  end

  defp redact_params(conn) do
    scrubbed = %{"token" => "[FILTERED]", "code" => "[FILTERED]"}

    %{
      conn
      | params: Map.put(conn.params, "operator", scrubbed),
        body_params: Map.put(conn.body_params, "operator", scrubbed)
    }
  end
end
