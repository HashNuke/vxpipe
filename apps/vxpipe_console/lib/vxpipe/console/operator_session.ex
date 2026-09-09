defmodule Vxpipe.Console.OperatorSession do
  @moduledoc "Serializes the non-secret operator identity in a signed browser session."

  alias Plug.Conn
  alias Vxpipe.Calls.Principal

  @session_key "vxpipe_operator"
  @live_session_key "vxpipe_operator_session"
  @known_scopes [:admin, :calls]
  @api_key_id_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  @spec put(Conn.t(), Principal.t(), keyword()) :: Conn.t()
  def put(%Conn{} = conn, %Principal{} = principal, options \\ []) do
    expires_at_unix = now_unix(options) + max_age_seconds(options)

    Conn.put_session(conn, @session_key, %{
      "api_key_id" => principal.api_key_id,
      "expires_at_unix" => expires_at_unix,
      "scopes" => encode_scopes(principal.scopes),
      "tenant_key" => principal.tenant_key
    })
  end

  @spec fetch(Conn.t(), keyword()) :: {:ok, Principal.t()} | :error
  def fetch(%Conn{} = conn, options \\ []) do
    conn
    |> Conn.get_session(@session_key)
    |> decode(now_unix(options))
  end

  @spec clear(Conn.t()) :: Conn.t()
  def clear(%Conn{} = conn), do: Conn.delete_session(conn, @session_key)

  @spec live_session(Conn.t()) :: map()
  def live_session(%Conn{} = conn) do
    %{@live_session_key => Conn.get_session(conn, @session_key)}
  end

  @spec fetch_live(map(), keyword()) :: {:ok, Principal.t()} | :error
  def fetch_live(session, options \\ []) when is_map(session) do
    session
    |> Map.get(@live_session_key)
    |> decode(now_unix(options))
  end

  defp decode(
         %{
           "api_key_id" => api_key_id,
           "expires_at_unix" => expires_at_unix,
           "scopes" => scopes,
           "tenant_key" => tenant_key
         },
         now_unix
       )
       when is_binary(api_key_id) and is_integer(expires_at_unix) and is_list(scopes) and
              is_binary(tenant_key) do
    with true <- byte_size(tenant_key) == 16,
         true <- Regex.match?(@api_key_id_pattern, api_key_id),
         true <- expires_at_unix > now_unix,
         {:ok, scopes} <- decode_scopes(scopes),
         true <- MapSet.member?(scopes, :calls) do
      {:ok,
       %Principal{
         api_key_id: api_key_id,
         scopes: scopes,
         tenant_key: tenant_key
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_value, _now_unix), do: :error

  defp encode_scopes(%MapSet{} = scopes) do
    @known_scopes
    |> Enum.filter(&MapSet.member?(scopes, &1))
    |> Enum.map(&Atom.to_string/1)
  end

  defp decode_scopes(scopes) do
    Enum.reduce_while(scopes, {:ok, MapSet.new()}, fn
      "admin", {:ok, result} -> {:cont, {:ok, MapSet.put(result, :admin)}}
      "calls", {:ok, result} -> {:cont, {:ok, MapSet.put(result, :calls)}}
      _scope, _result -> {:halt, :error}
    end)
  end

  defp now_unix(options),
    do: Keyword.get_lazy(options, :now_unix, fn -> System.system_time(:second) end)

  defp max_age_seconds(options) do
    max_age_seconds =
      Keyword.get_lazy(options, :max_age_seconds, fn ->
        :vxpipe_console
        |> Application.fetch_env!(:operator_session)
        |> Keyword.fetch!(:max_age_seconds)
      end)

    if is_integer(max_age_seconds) and max_age_seconds > 0 do
      max_age_seconds
    else
      raise ArgumentError, "operator session max_age_seconds must be a positive integer"
    end
  end
end
