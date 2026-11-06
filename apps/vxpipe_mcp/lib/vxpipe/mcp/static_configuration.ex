defmodule Vxpipe.MCP.StaticConfiguration do
  @moduledoc "Validated static connection input. Contains secrets; inspection is deliberately opaque."
  alias Vxpipe.MCP.Authentication

  @derive {Inspect, only: [:auth_method]}
  @enforce_keys [:endpoint, :auth_method, :secrets, :authentication]
  defstruct @enforce_keys

  def new(
        %{"endpoint" => endpoint, "auth_method" => method, "credentials" => credentials} = input
      ) do
    with true <- Map.keys(input) -- ~w(endpoint auth_method credentials) == [],
         {:ok, endpoint} <- endpoint(endpoint),
         {:ok, authentication} <- authentication(method, credentials) do
      {:ok,
       %__MODULE__{
         endpoint: endpoint,
         auth_method: method,
         secrets: credentials,
         authentication: authentication
       }}
    else
      false -> {:error, :invalid_mcp_configuration}
      {:error, _reason} = error -> error
    end
  end

  def new(_input), do: {:error, :invalid_mcp_configuration}

  def endpoint(value) when is_binary(value) and byte_size(value) in 1..2048 do
    with true <- String.valid?(value),
         false <- Regex.match?(~r/[\x00-\x20\x7f]/, value),
         {:ok, %URI{scheme: "https", host: host, port: port, userinfo: nil, fragment: nil} = uri} <-
           URI.new(value),
         true <- is_binary(host) and host != "" and port in 1..65_535 do
      {:ok, URI.to_string(%{uri | host: String.downcase(host), path: uri.path || "/"})}
    else
      _invalid -> {:error, :invalid_mcp_endpoint}
    end
  end

  def endpoint(_value), do: {:error, :invalid_mcp_endpoint}

  defp authentication("none", credentials) when credentials == %{}, do: {:ok, :none}

  defp authentication(method, credentials)
       when is_map(credentials) and not is_struct(credentials) do
    with {:ok, base, fields} <- base_authentication(method, credentials),
         true <- Map.keys(credentials) -- fields == [],
         {:ok, base_headers} <- Authentication.headers(base),
         {:ok, extra} <- extra_headers(Map.get(credentials, "headers", [])),
         {:ok, authentication} <- combine(base, base_headers, extra) do
      {:ok, authentication}
    else
      _invalid -> {:error, :invalid_mcp_authentication}
    end
  end

  defp authentication(_method, _credentials), do: {:error, :invalid_mcp_authentication}

  defp base_authentication("bearer", credentials),
    do: {:ok, [type: :bearer, token: credentials["token"]], ~w(token headers)}

  defp base_authentication("headers", %{"headers" => headers})
       when is_list(headers) and headers != [],
       do: {:ok, :none, ~w(headers)}

  defp base_authentication("basic", %{"username" => username, "password" => password})
       when is_binary(username) and is_binary(password) do
    if byte_size(username) in 1..1024 and byte_size(password) in 1..4096 and
         not String.contains?(username, ":") and printable?(username) and printable?(password) do
      value = "Basic " <> Base.encode64(username <> ":" <> password)

      {:ok, [type: :custom_headers, headers: [{"authorization", value}]],
       ~w(username password headers)}
    else
      {:error, :invalid_mcp_authentication}
    end
  end

  defp base_authentication(_method, _credentials), do: {:error, :invalid_mcp_authentication}

  defp extra_headers(headers) when is_list(headers) and length(headers) <= 32 do
    Enum.reduce_while(headers, {:ok, []}, fn
      %{"name" => name, "value" => value} = entry, {:ok, entries} when map_size(entry) == 2 ->
        {:cont, {:ok, [{name, value} | entries]}}

      _invalid, _entries ->
        {:halt, {:error, :invalid_mcp_authentication}}
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp extra_headers(_headers), do: {:error, :invalid_mcp_authentication}
  defp combine(base, _headers, []), do: {:ok, base}

  defp combine(_base, headers, extra) do
    authentication = [type: :custom_headers, headers: headers ++ extra]
    with {:ok, _validated} <- Authentication.headers(authentication), do: {:ok, authentication}
  end

  defp printable?(value), do: value |> :binary.bin_to_list() |> Enum.all?(&(&1 in 32..126))
end
