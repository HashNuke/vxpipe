defmodule Vxpipe.Console.InstallationOperatorSession do
  @moduledoc "Stores and validates the installation-wide operator browser grant."

  alias Plug.Conn
  alias Vxpipe.Console.{InstallationOperatorGrant, OperatorLoginConfiguration}

  @session_key "vxpipe_installation_operator"
  @authority "installation_operator"

  @spec put(Conn.t(), keyword()) :: Conn.t()
  def put(%Conn{} = conn, options \\ []) do
    issued_at_unix = now_unix(options)
    expires_at_unix = issued_at_unix + max_age_seconds(options)

    case OperatorLoginConfiguration.session_secret() do
      {:ok, secret} ->
        Conn.put_session(conn, @session_key, %{
          "authority" => @authority,
          "issued_at_unix" => issued_at_unix,
          "expires_at_unix" => expires_at_unix,
          "signature" => signature(secret, issued_at_unix, expires_at_unix)
        })

      {:error, :invalid_operator_login_secret} ->
        clear(conn)
    end
  end

  @spec fetch(Conn.t(), keyword()) :: {:ok, InstallationOperatorGrant.t()} | :error
  def fetch(%Conn{} = conn, options \\ []) do
    with {:ok, secret} <- OperatorLoginConfiguration.session_secret() do
      conn
      |> Conn.get_session(@session_key)
      |> decode(secret, now_unix(options))
    else
      {:error, :invalid_operator_login_secret} -> :error
    end
  end

  @spec clear(Conn.t()) :: Conn.t()
  def clear(%Conn{} = conn), do: Conn.delete_session(conn, @session_key)

  defp decode(
         %{
           "authority" => @authority,
           "issued_at_unix" => issued_at_unix,
           "expires_at_unix" => expires_at_unix,
           "signature" => supplied_signature
         },
         secret,
         now_unix
       )
       when is_integer(issued_at_unix) and is_integer(expires_at_unix) and
              issued_at_unix <= now_unix and expires_at_unix > now_unix and
              expires_at_unix > issued_at_unix and is_binary(supplied_signature) do
    expected_signature = signature(secret, issued_at_unix, expires_at_unix)

    if Plug.Crypto.secure_compare(expected_signature, supplied_signature) do
      {:ok,
       %InstallationOperatorGrant{
         issued_at_unix: issued_at_unix,
         expires_at_unix: expires_at_unix
       }}
    else
      :error
    end
  end

  defp decode(_value, _secret, _now_unix), do: :error

  defp signature(secret, issued_at_unix, expires_at_unix) do
    payload = "#{@authority}:#{issued_at_unix}:#{expires_at_unix}"

    :hmac
    |> :crypto.mac(:sha256, secret, payload)
    |> Base.url_encode64(padding: false)
  end

  defp now_unix(options),
    do: Keyword.get_lazy(options, :now_unix, fn -> System.system_time(:second) end)

  defp max_age_seconds(options) do
    max_age_seconds =
      Keyword.get_lazy(options, :max_age_seconds, fn ->
        :vxpipe_console
        |> Application.fetch_env!(:installation_operator_session)
        |> Keyword.fetch!(:max_age_seconds)
      end)

    if is_integer(max_age_seconds) and max_age_seconds > 0 do
      max_age_seconds
    else
      raise ArgumentError, "installation operator session max_age_seconds must be positive"
    end
  end
end
